import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: permissionIcon)
                            .foregroundColor(permissionColor)
                            .font(.obsidianHeadline)
                            .frame(width: 34, height: 34)
                            .background(permissionColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notification Permission")
                                .font(.obsidianCallout)
                                .foregroundColor(.textPrimary)
                                .accessibilityIdentifier("notificationSettingsScreen")

                            Text(permissionStatusText)
                                .font(.obsidianFootnote)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        if authorizationStatus == .denied || authorizationStatus == .notDetermined {
                            Button("Enable") {
                                requestPermissionOrOpenSettings()
                            }
                            .buttonStyle(ObsidianSecondaryButtonStyle())
                            .controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Permission")
                        .microLabel()
                } footer: {
                    Text("Notifications are required to remind you about appointments and follow-ups.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()

                Section {
                    Toggle("Play Sound", isOn: $notificationService.notificationSettings.playSound)
                        .onChange(of: notificationService.notificationSettings.playSound) {
                            saveSettings()
                        }
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                        .accessibilityIdentifier("notificationPlaySoundToggle")
                } header: {
                    Text("Sound")
                        .microLabel()
                } footer: {
                    Text("Turn off to receive silent notifications.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()

                Section {
                    Toggle("Follow-up Reminders", isOn: $notificationService.notificationSettings.followUpReminders.isEnabled)
                        .onChange(of: notificationService.notificationSettings.followUpReminders.isEnabled) {
                            saveSettings()
                        }
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                        .accessibilityIdentifier("notificationFollowUpRemindersToggle")

                    if notificationService.notificationSettings.followUpReminders.isEnabled {
                        Picker("Reminder Time", selection: $notificationService.notificationSettings.followUpReminders.reminderTime) {
                            ForEach(FollowUpReminderTime.allCases, id: \.self) { time in
                                Text(time.displayName).tag(time)
                            }
                        }
                        .onChange(of: notificationService.notificationSettings.followUpReminders.reminderTime) {
                            saveSettings()
                        }
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                    }
                } header: {
                    Text("Follow-up Reminders")
                        .microLabel()
                } footer: {
                    Text("Get notified when it's time to follow up with leads.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()

                Section {
                    Toggle("Appointment Reminders", isOn: $notificationService.notificationSettings.appointmentReminders.isEnabled)
                        .onChange(of: notificationService.notificationSettings.appointmentReminders.isEnabled) {
                            saveSettings()
                        }
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                        .accessibilityIdentifier("notificationAppointmentRemindersToggle")

                    if notificationService.notificationSettings.appointmentReminders.isEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reminder Times")
                                .font(.obsidianFootnote)
                                .foregroundColor(.textSecondary)

                            ForEach(AppointmentReminderTime.allCases, id: \.self) { reminderTime in
                                Button(action: {
                                    toggleReminderTime(reminderTime)
                                }) {
                                    HStack {
                                        Image(systemName: isReminderTimeSelected(reminderTime) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isReminderTimeSelected(reminderTime) ? .electricViolet : .textMuted)
                                        Text(reminderTime.displayName + " before")
                                            .font(.obsidianBody)
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Appointment Reminders")
                        .microLabel()
                } footer: {
                    Text("Choose when to be reminded about upcoming appointments.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()

                Section {
                    Toggle("Daily Summary", isOn: $notificationService.notificationSettings.dailySummary.isEnabled)
                        .onChange(of: notificationService.notificationSettings.dailySummary.isEnabled) {
                            saveSettings()
                        }
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                        .accessibilityIdentifier("notificationDailySummaryToggle")

                    if notificationService.notificationSettings.dailySummary.isEnabled {
                        DatePicker("Summary Time", selection: $notificationService.notificationSettings.dailySummary.time, displayedComponents: .hourAndMinute)
                            .onChange(of: notificationService.notificationSettings.dailySummary.time) {
                                saveSettings()
                            }
                            .font(.obsidianBody)
                            .foregroundColor(.textPrimary)
                    }
                } header: {
                    Text("Daily Summary")
                        .microLabel()
                } footer: {
                    Text("Get a daily overview of your appointments and follow-ups.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()

                Section {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundColor(.statusNotInterested)
                    .accessibilityIdentifier("notificationResetDefaultsButton")

                    Button("Refresh All Notifications") {
                        notificationService.refreshAllNotifications()
                    }
                    .foregroundColor(.electricViolet)
                    .accessibilityIdentifier("notificationRefreshAllButton")
                } header: {
                    Text("Management")
                        .microLabel()
                } footer: {
                    Text("Reset all notification settings or refresh pending notifications.")
                        .foregroundColor(.textSecondary)
                }
                .obsidianListRow()
            }
            .navigationTitle("Notifications")
            .obsidianInlineNavigation()
            .obsidianListScreen()
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
