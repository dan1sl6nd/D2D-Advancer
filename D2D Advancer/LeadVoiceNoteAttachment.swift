import SwiftUI
import AVFoundation
import Speech
import CoreData

private func deactivateVoiceNoteAudioSession(context: String) {
    do {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    } catch {
        print("⚠️ VoiceNote: audio session deactivate failed during \(context): \(error.localizedDescription)")
    }
}

// MARK: - Recorder

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var meterLevel: Double = 0   // 0...1, normalized for the wave-pulse animation
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var fileURL: URL?

    /// Start recording to a temporary AAC file (~32 kbps mono). Returns true
    /// if recording actually started; false on permission denial / IO error.
    @discardableResult
    func start() async -> Bool {
        lastError = nil

        let granted = await Self.requestMicrophonePermission()
        guard granted else {
            lastError = "Microphone permission denied. Enable it in Settings → D2D Advancer."
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
            deactivateVoiceNoteAudioSession(context: "recording setup failure")
            lastError = "Audio session setup failed: \(error.localizedDescription)"
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-\(UUID().uuidString).m4a")

        // 22050 Hz mono AAC at 32 kbps balances voice clarity vs. file size.
        // 30 seconds ≈ 120 KB which streams to CloudKit in well under a second.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32_000
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()
            guard newRecorder.record() else {
                lastError = "Recorder failed to start."
                deactivateVoiceNoteAudioSession(context: "recorder start failure")
                return false
            }
            recorder = newRecorder
            fileURL = url
            isRecording = true
            elapsed = 0
            startMeterTimer()
            return true
        } catch {
            deactivateVoiceNoteAudioSession(context: "recorder creation failure")
            lastError = "Could not start recording: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        let url = fileURL
        recorder = nil
        // Politely release the audio session so background music apps
        // (Spotify, Apple Music) can reclaim the audio route immediately.
        // notifyOthersOnDeactivation tells other apps the route is free.
        deactivateVoiceNoteAudioSession(context: "recording stop")
        return url
    }

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let dB = recorder.averagePower(forChannel: 0)
                // dB is roughly -160 (silent) to 0 (peak). Compress to 0..1 with
                // a -50 floor so silent moments don't shrink the animation flat.
                let normalized = max(0, min(1, (dB + 50) / 50))
                self.meterLevel = Double(normalized)
                self.elapsed = recorder.currentTime
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - Player

@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var coordinator: PlayerCoordinator?

    func play(data: Data) {
        if isPlaying { pause(); return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(data: data)
            let coord = PlayerCoordinator { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackEnded()
                }
            }
            newPlayer.delegate = coord
            newPlayer.prepareToPlay()
            duration = newPlayer.duration
            newPlayer.play()
            player = newPlayer
            coordinator = coord
            isPlaying = true
            startTimer()
        } catch {
            deactivateVoiceNoteAudioSession(context: "playback failure")
            print("⚠️ VoiceNote: playback failed (\(error.localizedDescription))")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        coordinator = nil
        isPlaying = false
        elapsed = 0
        stopTimer()
        // Same deactivate-with-notify pattern as the recorder — frees the
        // playback route for whatever audio app the user wants to return to.
        deactivateVoiceNoteAudioSession(context: "playback stop")
    }

    private func handlePlaybackEnded() {
        // Same teardown as explicit stop, but preserve the duration so the UI
        // can render the "0:00 / 0:30" hint after a clip finishes.
        player = nil
        coordinator = nil
        isPlaying = false
        elapsed = 0
        stopTimer()
        deactivateVoiceNoteAudioSession(context: "playback finished")
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let p = self.player else { return }
                self.elapsed = p.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// AVAudioPlayer's delegate must inherit NSObject. We keep it as a tiny
/// adapter to call back into the @MainActor-isolated player without
/// inheritance gymnastics on the @MainActor class itself.
private final class PlayerCoordinator: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - Transcription

enum VoiceNoteTranscriber {
    static func transcribe(fileURL: URL) async -> String? {
        let authorized = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else {
            print("⚠️ VoiceNote: speech recognition not authorized")
            return nil
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            print("⚠️ VoiceNote: speech recognizer unavailable for current locale")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error = error {
                    print("⚠️ VoiceNote: transcription error \(error.localizedDescription)")
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }
                if let result = result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

// MARK: - SwiftUI Section

struct LeadVoiceNoteSection: View {
    @ObservedObject var lead: Lead
    @Environment(\.managedObjectContext) private var context

    @StateObject private var recorder = VoiceNoteRecorder()
    @StateObject private var player = VoiceNotePlayer()

    @State private var showingRecorder = false
    @State private var isProcessing = false
    @State private var recordingErrorMessage: String?

    private var hasVoiceNote: Bool {
        guard let data = lead.voiceNote else { return false }
        return !data.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Voice Note", systemImage: "waveform")
                .font(.obsidianCaption)
                .foregroundColor(Color.textSecondary)

            if hasVoiceNote {
                voiceNoteCard
                HStack(spacing: 8) {
                    inlineActionButton(title: "Re-record", icon: "mic.fill", destructive: false) {
                        player.stop()
                        showingRecorder = true
                    }
                    inlineActionButton(title: "Remove", icon: "trash.fill", destructive: true) {
                        removeVoiceNote()
                    }
                }
            } else {
                addButton
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(Color.electricViolet)
                    Text("Transcribing…")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.textSecondary)
                }
                .padding(.top, 2)
            }

            if let recordingErrorMessage {
                Text(recordingErrorMessage)
                    .font(.obsidianSmall)
                    .foregroundColor(Color.statusNotInterested)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingRecorder) {
            VoiceRecorderSheet(recorder: recorder) { url in
                if let url = url { handleNewRecording(url: url) }
            }
        }
    }

    private func inlineActionButton(
        title: String,
        icon: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint = destructive ? Color.statusNotInterested : Color.electricViolet
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text(title)
                    .font(.obsidianCaption)
                    .fontWeight(.medium)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: { showingRecorder = true }) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.obsidianCallout)
                Text("Record Voice Note")
                    .font(.obsidianFootnote)
                    .fontWeight(.medium)
            }
            .foregroundColor(Color.electricViolet)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.electricViolet.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.electricViolet.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private var voiceNoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.electricViolet)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let date = lead.voiceNoteCapturedDate {
                        Text("Recorded \(relativeDate(date))")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                    }
                    if player.duration > 0 {
                        Text(formatTime(player.elapsed) + " / " + formatTime(player.duration))
                            .font(.obsidianCaption)
                            .foregroundColor(Color.textMuted)
                            .monospacedDigit()
                    } else {
                        Text("Tap play to listen")
                            .font(.obsidianCaption)
                            .foregroundColor(Color.textMuted)
                    }
                }

                Spacer()
            }

            if let transcript = lead.voiceNoteTranscript, !transcript.isEmpty {
                Text(transcript)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.obsidianElevated)
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.obsidianSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private func togglePlayback() {
        guard let data = lead.voiceNote else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play(data: data)
        }
    }

    private func handleNewRecording(url: URL) {
        Task {
            await MainActor.run {
                recordingErrorMessage = nil
                isProcessing = true
            }

            // Transcribe first while the temp file exists
            let transcript = await VoiceNoteTranscriber.transcribe(fileURL: url)

            // Read bytes and persist
            let audioData: Data
            do {
                audioData = try Data(contentsOf: url)
            } catch {
                await MainActor.run {
                    isProcessing = false
                    recordingErrorMessage = "Could not save voice note. Please record it again."
                }
                cleanupTemporaryRecording(at: url)
                print("❌ Voice note temp file read failed: \(error.localizedDescription)")
                return
            }

            await MainActor.run {
                lead.voiceNote = audioData
                lead.voiceNoteCapturedDate = Date()
                lead.voiceNoteTranscript = transcript
                lead.updatedDate = Date()
                saveContext()
                isProcessing = false
                print("🎙 Voice note attached — \(audioData.count / 1024) KB, transcript \(transcript == nil ? "unavailable" : "ready")")
            }

            // Clean up temp file
            cleanupTemporaryRecording(at: url)
        }
    }

    private func removeVoiceNote() {
        player.stop()
        lead.voiceNote = nil
        lead.voiceNoteTranscript = nil
        lead.voiceNoteCapturedDate = nil
        lead.updatedDate = Date()
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ Voice note save failed: \(error.localizedDescription)")
            recordingErrorMessage = "Could not save voice note. Please try again."
            context.rollback()
        }
    }

    private func cleanupTemporaryRecording(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("⚠️ Voice note temp cleanup failed: \(error.localizedDescription)")
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Recorder Sheet

struct VoiceRecorderSheet: View {
    @ObservedObject var recorder: VoiceNoteRecorder
    let onComplete: (URL?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.obsidianBackground(for: colorScheme).ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                pulsingMic

                Text(formatTime(recorder.elapsed))
                    .font(.system(size: 44, weight: .light, design: .monospaced))
                    .foregroundColor(Color.textPrimary)

                if let error = recorder.lastError {
                    Text(error)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.statusNotInterested)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer()

                actionButton

                Button(action: cancel) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.obsidianTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("voiceRecorderCancelButton")

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 24)
        }
        .obsidianModalBackground()
        // Prevent swipe-down dismissal while recording — if the user swipes
        // away mid-record we'd leave the recorder running invisibly and the
        // audio session active. Forcing them to use Stop/Cancel guarantees
        // proper teardown.
        .interactiveDismissDisabled(recorder.isRecording)
        // Belt-and-suspenders: if the sheet disappears for any other reason
        // (interactive-dismiss when not recording, programmatic dismiss, etc.)
        // and a recording is somehow still in flight, stop it and clean up
        // the orphaned temp file.
        .onDisappear {
            if recorder.isRecording {
                if let url = recorder.stop() {
                    discardTemporaryRecording(at: url)
                }
            }
        }
    }

    private var pulsingMic: some View {
        ZStack {
            Circle()
                .fill(Color.electricViolet.opacity(0.18))
                .frame(width: 200, height: 200)
                .scaleEffect(recorder.isRecording ? 1.0 + (recorder.meterLevel * 0.4) : 1.0)
                .animation(.easeOut(duration: 0.12), value: recorder.meterLevel)

            Circle()
                .fill(Color.electricViolet)
                .frame(width: 110, height: 110)

            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: recorder.isRecording)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if recorder.isRecording {
            Button(action: stop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.obsidianAction)
                    Text("Stop & Save")
                        .font(.obsidianTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianDangerButtonStyle())
        } else {
            Button(action: start) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.obsidianAction)
                    Text("Start Recording")
                        .font(.obsidianTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
        }
    }

    private func start() {
        Task { await recorder.start() }
    }

    private func stop() {
        let url = recorder.stop()
        onComplete(url)
        dismiss()
    }

    private func cancel() {
        // Discard any in-progress recording and delete the orphan temp file
        // before reporting cancellation upward.
        if recorder.isRecording, let url = recorder.stop() {
            discardTemporaryRecording(at: url)
        }
        onComplete(nil)
        dismiss()
    }

    private func discardTemporaryRecording(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("⚠️ Voice recorder temp cleanup failed: \(error.localizedDescription)")
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let tenths = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, tenths)
    }
}
