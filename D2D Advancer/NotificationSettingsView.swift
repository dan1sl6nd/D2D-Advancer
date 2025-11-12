import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false

    var body: some View {
        NavigationView {
            List {
                // Permission Status Section
                Section {
                    HStack {
                        Image(systemName: permissionIcon)
                            .foregroundColor(permissionColor)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notification Permission")
                                .font(.headline)

                            Text(permissionStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if authorizationStatus == .denied || authorizationStatus == .notDetermined {
                            Button("Enable") {
                                requestPermissionOrOpenSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Permission")
                } footer: {
                    Text("Notifications are required to remind you about appointments and follow-ups.")
                }

                // Global Sound Setting
                Section {
                    Toggle("Play Sound", isOn: $notificationService.notificationSettings.playSound)
                        .onChange(of: notificationService.notificationSettings.playSound) {
                            saveSettings()
                        }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Turn off to receive silent notifications.")
                }

                // Follow-up Reminders Section
                Section {
                    Toggle("Follow-up Reminders", isOn: $notificationService.notificationSettings.followUpReminders.isEnabled)
                        .onChange(of: notificationService.notificationSettings.followUpReminders.isEnabled) {
                            saveSettings()
                        }

                    if notificationService.notificationSettings.followUpReminders.isEnabled {
                        Picker("Reminder Time", selection: $notificationService.notificationSettings.followUpReminders.reminderTime) {
                            ForEach(FollowUpReminderTime.allCases, id: \.self) { time in
                                Text(time.displayName).tag(time)
                            }
                        }
                        .onChange(of: notificationService.notificationSettings.followUpReminders.reminderTime) {
                            saveSettings()
                        }
                    }
                } header: {
                    Text("Follow-up Reminders")
                } footer: {
                    Text("Get notified when it's time to follow up with leads.")
                }

                // Appointment Reminders Section
                Section {
                    Toggle("Appointment Reminders", isOn: $notificationService.notificationSettings.appointmentReminders.isEnabled)
                        .onChange(of: notificationService.notificationSettings.appointmentReminders.isEnabled) {
                            saveSettings()
                        }

                    if notificationService.notificationSettings.appointmentReminders.isEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reminder Times")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            ForEach(AppointmentReminderTime.allCases, id: \.self) { reminderTime in
                                HStack {
                                    Button(action: {
                                        toggleReminderTime(reminderTime)
                                    }) {
                                        HStack {
                                            Image(systemName: isReminderTimeSelected(reminderTime) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isReminderTimeSelected(reminderTime) ? .blue : .gray)
                                            Text(reminderTime.displayName + " before")
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Appointment Reminders")
                } footer: {
                    Text("Choose when to be reminded about upcoming appointments.")
                }

                // Daily Summary Section
                Section {
                    Toggle("Daily Summary", isOn: $notificationService.notificationSettings.dailySummary.isEnabled)
                        .onChange(of: notificationService.notificationSettings.dailySummary.isEnabled) {
                            saveSettings()
                        }

                    if notificationService.notificationSettings.dailySummary.isEnabled {
                        DatePicker("Summary Time", selection: $notificationService.notificationSettings.dailySummary.time, displayedComponents: .hourAndMinute)
                            .onChange(of: notificationService.notificationSettings.dailySummary.time) {
                                saveSettings()
                            }
                    }
                } header: {
                    Text("Daily Summary")
                } footer: {
                    Text("Get a daily overview of your appointments and follow-ups.")
                }

                // Reset Section
                Section {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundColor(.red)

                    Button("Refresh All Notifications") {
                        notificationService.refreshAllNotifications()
                    }
                    .foregroundColor(.blue)
                } header: {
                    Text("Management")
                } footer: {
                    Text("Reset all notification settings or refresh pending notifications.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
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
        notificationService.updateSettings(notificationService.notificationSettings)

        // Refresh notifications with new settings
        notificationService.refreshAllNotifications()
    }

    private func resetToDefaults() {
        notificationService.updateSettings(NotificationSettings())
        notificationService.refreshAllNotifications()
    }
}

#Preview {
    NotificationSettingsView()
}