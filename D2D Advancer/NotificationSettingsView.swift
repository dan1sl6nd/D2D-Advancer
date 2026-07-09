import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ObsidianScreenTitle(
                    title: "Notifications",
                    subtitle: "Control sounds, reminders, and the daily summary.",
                    icon: "bell.fill"
                )
                .accessibilityIdentifier("notificationSettingsScreen")

                permissionSection
                reminderSection
                dailySummarySection
                managementSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .obsidianScreenBackground()
        .obsidianPushedNavigation("Notifications", backButtonAccessibilityIdentifier: "notificationSettingsBackButton")
        .onAppear {
            checkPermissionStatus()
        }
        .alert("Notification Permission", isPresented: $showingPermissionAlert) {
            Button("Go to Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Notifications are disabled in Settings. Enable them to receive reminders about appointments and follow-ups.")
        }
        .alert("Notification settings not saved", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Notification settings were not saved.")
        }
    }

    private var permissionSection: some View {
        MoreSectionGroup(
            title: "Permission",
            icon: permissionIcon,
            subtitle: "Required for appointment and follow-up reminders.",
            accentColor: permissionColor
        ) {
            MoreCardView(
                icon: permissionIcon,
                iconColor: permissionColor,
                title: "Notification Permission",
                subtitle: permissionStatusText,
                trailingContent: {
                    if authorizationStatus == .denied || authorizationStatus == .notDetermined {
                        Button("Enable") {
                            requestPermissionOrOpenSettings()
                        }
                        .buttonStyle(ObsidianSecondaryButtonStyle())
                    }
                }
            )
        }
    }

    private var reminderSection: some View {
        MoreSectionGroup(
            title: "Reminders",
            icon: "clock.badge.checkmark",
            subtitle: "Tune the alerts that matter in the field.",
            accentColor: Color.electricViolet
        ) {
            MoreCardView(
                icon: "speaker.wave.2.fill",
                iconColor: Color.statusInterested,
                title: "Play Sound",
                subtitle: "Turn off for silent notifications",
                trailingContent: {
                    Toggle("Play Sound", isOn: $notificationService.notificationSettings.playSound)
                        .labelsHidden()
                        .onChange(of: notificationService.notificationSettings.playSound) {
                            saveSettings()
                        }
                        .accessibilityIdentifier("notificationPlaySoundToggle")
                }
            )

            notificationDivider

            MoreCardView(
                icon: "person.crop.circle.badge.clock",
                iconColor: Color.statusNotHome,
                title: "Follow-up Reminders",
                subtitle: "Get notified when leads are due",
                trailingContent: {
                    Toggle("Follow-up Reminders", isOn: $notificationService.notificationSettings.followUpReminders.isEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.notificationSettings.followUpReminders.isEnabled) {
                            saveSettings()
                        }
                        .accessibilityIdentifier("notificationFollowUpRemindersToggle")
                }
            )

            if notificationService.notificationSettings.followUpReminders.isEnabled {
                notificationDivider

                MoreCardView(
                    icon: "clock.arrow.circlepath",
                    iconColor: Color.statusNotHome,
                    title: "Follow-up Timing",
                    subtitle: "When follow-up alerts fire",
                    trailingContent: {
                        followUpReminderTimeMenu
                    }
                )
            }

            notificationDivider

            MoreCardView(
                icon: "calendar.badge.clock",
                iconColor: Color.electricViolet,
                title: "Appointment Reminders",
                subtitle: "Alert before scheduled work",
                trailingContent: {
                    Toggle("Appointment Reminders", isOn: $notificationService.notificationSettings.appointmentReminders.isEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.notificationSettings.appointmentReminders.isEnabled) {
                            saveSettings()
                        }
                        .accessibilityIdentifier("notificationAppointmentRemindersToggle")
                }
            )

            if notificationService.notificationSettings.appointmentReminders.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reminder Times")
                        .microLabel()
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    ForEach(AppointmentReminderTime.allCases, id: \.self) { reminderTime in
                        reminderTimeButton(reminderTime)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var dailySummarySection: some View {
        MoreSectionGroup(
            title: "Daily Summary",
            icon: "sunrise.fill",
            subtitle: "Start the day with a compact workload overview.",
            accentColor: Color.statusInterested
        ) {
            MoreCardView(
                icon: "doc.text.magnifyingglass",
                iconColor: Color.statusInterested,
                title: "Daily Summary",
                subtitle: "Appointments and follow-ups overview",
                trailingContent: {
                    Toggle("Daily Summary", isOn: $notificationService.notificationSettings.dailySummary.isEnabled)
                        .labelsHidden()
                        .onChange(of: notificationService.notificationSettings.dailySummary.isEnabled) {
                            saveSettings()
                        }
                        .accessibilityIdentifier("notificationDailySummaryToggle")
                }
            )

            if notificationService.notificationSettings.dailySummary.isEnabled {
                notificationDivider

                MoreCardView(
                    icon: "clock.fill",
                    iconColor: Color.statusInterested,
                    title: "Summary Time",
                    subtitle: "When the daily overview arrives",
                    trailingContent: {
                        DatePicker(
                            "Summary Time",
                            selection: $notificationService.notificationSettings.dailySummary.time,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .onChange(of: notificationService.notificationSettings.dailySummary.time) {
                            saveSettings()
                        }
                    }
                )
            }
        }
    }

    private var managementSection: some View {
        MoreSectionGroup(
            title: "Management",
            icon: "wrench.and.screwdriver.fill",
            subtitle: "Reset settings or rebuild scheduled notifications.",
            accentColor: Color.statusNotInterested
        ) {
            VStack(spacing: 12) {
                Button {
                    resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("notificationResetDefaultsButton")

                Button {
                    notificationService.refreshAllNotifications()
                } label: {
                    Label("Refresh All Notifications", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("notificationRefreshAllButton")
            }
            .padding(16)
        }
    }

    private var notificationDivider: some View {
        Rectangle()
            .fill(Color.obsidianBorder.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private var followUpReminderTimeMenu: some View {
        Menu {
            ForEach(FollowUpReminderTime.allCases, id: \.self) { time in
                Button {
                    notificationService.notificationSettings.followUpReminders.reminderTime = time
                    saveSettings()
                } label: {
                    if notificationService.notificationSettings.followUpReminders.reminderTime == time {
                        Label(time.displayName, systemImage: "checkmark")
                    } else {
                        Text(time.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(compactFollowUpReminderTimeLabel(notificationService.notificationSettings.followUpReminders.reminderTime))
                    .font(.obsidianFootnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: "chevron.down")
                    .font(.micro)
            }
            .foregroundColor(Color.electricViolet)
            .padding(.horizontal, 10)
            .frame(minWidth: 118, minHeight: 44)
            .background(Color.electricViolet.opacity(0.12))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .accessibilityIdentifier("notificationFollowUpReminderTimeMenu")
    }

    private func compactFollowUpReminderTimeLabel(_ time: FollowUpReminderTime) -> String {
        switch time {
        case .atTime:
            return "At time"
        case .fifteenMinutesBefore:
            return "15 min before"
        case .thirtyMinutesBefore:
            return "30 min before"
        case .oneHourBefore:
            return "1 hr before"
        }
    }

    private func reminderTimeButton(_ reminderTime: AppointmentReminderTime) -> some View {
        Button {
            toggleReminderTime(reminderTime)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isReminderTimeSelected(reminderTime) ? "checkmark.circle.fill" : "circle")
                    .font(.obsidianCallout)
                    .foregroundColor(isReminderTimeSelected(reminderTime) ? .electricViolet : .textMuted)

                Text(reminderTime.displayName + " before")
                    .font(.obsidianBody)
                    .foregroundColor(.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var permissionIcon: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var permissionStatusText: String {
        switch authorizationStatus {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied - Tap to enable in Settings"
        case .notDetermined:
            return "Not requested - Tap to enable"
        case .provisional:
            return "Provisional access"
        case .ephemeral:
            return "Ephemeral access"
        @unknown default:
            return "Unknown status"
        }
    }

    private func checkPermissionStatus() {
        notificationService.checkNotificationPermission { status in
            authorizationStatus = status
        }
    }

    private func requestPermissionOrOpenSettings() {
        if authorizationStatus == .denied {
            showingPermissionAlert = true
        } else {
            notificationService.requestNotificationPermission { granted in
                checkPermissionStatus()
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func isReminderTimeSelected(_ reminderTime: AppointmentReminderTime) -> Bool {
        notificationService.notificationSettings.appointmentReminders.reminderTimes.contains(reminderTime)
    }

    private func toggleReminderTime(_ reminderTime: AppointmentReminderTime) {
        var currentTimes = notificationService.notificationSettings.appointmentReminders.reminderTimes

        if currentTimes.contains(reminderTime) {
            currentTimes.removeAll { $0 == reminderTime }
        } else {
            currentTimes.append(reminderTime)
        }

        notificationService.notificationSettings.appointmentReminders.reminderTimes = currentTimes
        saveSettings()
    }

    private func saveSettings() {
        guard notificationService.updateSettings(notificationService.notificationSettings) else {
            saveErrorMessage = notificationService.lastErrorMessage ?? "Notification settings were not saved."
            return
        }

        // Refresh notifications with new settings
        notificationService.refreshAllNotifications()
    }

    private func resetToDefaults() {
        guard notificationService.updateSettings(NotificationSettings()) else {
            saveErrorMessage = notificationService.lastErrorMessage ?? "Notification settings were not saved."
            return
        }
        notificationService.refreshAllNotifications()
    }
}

#Preview {
    NotificationSettingsView()
}
