import SwiftUI
import PhotosUI
import CoreData
import UIKit

// MARK: - Photo section embedded inside a lead detail / edit view

/// Drop-in section that shows a lead's photo and lets the user capture,
/// replace, or remove it. Writes directly to the managed object context
/// — NSPersistentCloudKitContainer mirrors the bytes to CloudKit as a
/// CKAsset automatically thanks to `allowsExternalBinaryDataStorage`.
struct LeadPhotoSection: View {
    @ObservedObject var lead: Lead
    @Environment(\.managedObjectContext) private var context

    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingFullscreen = false
    @State private var libraryItem: PhotosPickerItem?

    private var photoImage: UIImage? {
        guard let data = lead.photo, !data.isEmpty else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Photo", systemImage: "photo.fill")
                .font(.obsidianCaption)
                .foregroundColor(Color.textSecondary)

            photoCard

            // Inline actions row, only shown when a photo is attached. Replaced
            // the 3-dots Menu/confirmationDialog approach because SwiftUI's
            // dialog presentation was unreliable for the styled trigger buttons.
            if photoImage != nil {
                HStack(spacing: 8) {
                    inlineActionButton(title: "Take Photo", icon: "camera.fill", destructive: false) {
                        showingCamera = true
                    }
                    inlineActionButton(title: "Library", icon: "photo.on.rectangle.angled", destructive: false) {
                        showingLibrary = true
                    }
                    inlineActionButton(title: "Remove", icon: "trash.fill", destructive: true) {
                        removePhoto()
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                saveImage(image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showingLibrary,
            selection: $libraryItem,
            matching: .images
        )
        .onChange(of: libraryItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        saveImage(image)
                        libraryItem = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let img = photoImage {
                FullscreenPhotoViewer(image: img) {
                    showingFullscreen = false
                }
            }
        }
    }

    // MARK: - Photo Card

    @ViewBuilder
    private var photoCard: some View {
        if let img = photoImage {
            existingPhoto(img)
        } else {
            addPhotoButtons
        }
    }

    private func existingPhoto(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
            )
            .overlay(alignment: .bottomLeading) {
                if let date = lead.photoCapturedDate {
                    Text(relativeDate(date))
                        .font(.obsidianSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(10)
                }
            }
            .onTapGesture {
                showingFullscreen = true
            }
    }

    private var addPhotoButtons: some View {
        HStack(spacing: 10) {
            sourceButton(title: "Take Photo", icon: "camera.fill") {
                showingCamera = true
            }
            sourceButton(title: "Library", icon: "photo.on.rectangle.angled") {
                showingLibrary = true
            }
        }
    }

    private func sourceButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sourceButtonLabel(title: title, icon: icon)
        }
    }

    private func sourceButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.obsidianCallout)
            Text(title)
                .font(.obsidianFootnote)
                .fontWeight(.medium)
        }
        .foregroundColor(Color.electricViolet)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.electricViolet.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.electricViolet.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Compact inline action button used below an existing photo. Smaller
    /// vertical padding than the "add photo" buttons since the photo above
    /// is the primary visual element.
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Persistence

    private func saveImage(_ image: UIImage) {
        guard let compressed = PhotoCompressor.compress(image) else {
            print("⚠️ Photo: compression produced nil data")
            return
        }
        lead.photo = compressed
        lead.photoCapturedDate = Date()
        lead.updatedDate = Date()
        saveContext()
        print("📷 Photo attached to lead \(lead.id?.uuidString ?? "?") — \(compressed.count / 1024) KB")
    }

    private func removePhoto() {
        lead.photo = nil
        lead.photoCapturedDate = nil
        lead.updatedDate = Date()
        saveContext()
        print("🗑️ Photo removed from lead \(lead.id?.uuidString ?? "?")")
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ Photo save failed: \(error.localizedDescription)")
            context.rollback()
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Camera wrapper (UIImagePickerController)

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Fullscreen viewer

private struct FullscreenPhotoViewer: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // Fit-to-screen by default (aspectRatio .fit + filling the ZStack
            // gives a natural "letterboxed" rendering). Pinch zooms; drag pans
            // when zoomed in. Double-tap toggles between 1× and 2×.
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let target = committedScale * value
                                scale = min(max(target, 1), 5)
                            }
                            .onEnded { _ in
                                committedScale = scale
                                if scale < 1.02 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1
                                        committedScale = 1
                                        offset = .zero
                                        committedOffset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: committedOffset.width + value.translation.width,
                                    height: committedOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                committedOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1.5 {
                            scale = 1
                            committedScale = 1
                            offset = .zero
                            committedOffset = .zero
                        } else {
                            scale = 2
                            committedScale = 2
                        }
                    }
                }
                .onTapGesture(count: 1) {
                    if scale <= 1.02 { onClose() }
                }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.obsidianCaption.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Compression helper

enum PhotoCompressor {
    /// Scale the image so its longest edge is at most `maxDimension`, then
    /// re-encode as JPEG at the given quality. For 3:4 iPhone camera output
    /// this typically yields 150–400 KB — small enough to keep CloudKit
    /// sync snappy and large enough that the photo is still clearly
    /// recognizable at full-screen viewing.
    static func compress(
        _ image: UIImage,
        maxDimension: CGFloat = 1920,
        quality: CGFloat = 0.6
    ) -> Data? {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > 0 else { return nil }

        let scale = longestEdge > maxDimension ? maxDimension / longestEdge : 1.0
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: quality)
    }
}
