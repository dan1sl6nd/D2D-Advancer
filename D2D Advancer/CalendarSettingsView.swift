import SwiftUI
import EventKit
import UIKit

struct CalendarSettingsView: View {
    @ObservedObject private var calendarService = CalendarService.shared

    @State private var calendars: [EKCalendar] = []
    @State private var hasLoadedCalendars = false
    @State private var showDeniedAlert = false
    @State private var settingsErrorMessage: String?

    var body: some View {
        List {
            Section("Apple Calendar") {
                Toggle("Add appointments to Apple Calendar", isOn: Binding(
                    get: { calendarService.settings.isEnabled },
                    set: { isEnabled in
                        updateCalendarSettings { settings in
                            settings.isEnabled = isEnabled
                        }
                    }
                ))
                .font(.obsidianBody)
                .foregroundColor(.textPrimary)
                .accessibilityIdentifier("calendarSettingsEnableToggle")

                if !calendarService.hasWriteAccessOrBetter {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.obsidianCallout)
                            .foregroundColor(.statusNotHome)
                            .frame(width: 34, height: 34)
                            .background(Color.statusNotHome.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Calendar access not granted")
                            .font(.obsidianBody)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button("Allow") { requestAccess() }
                            .buttonStyle(ObsidianSecondaryButtonStyle())
                    }
                }
            }
            .textCase(nil)
            .obsidianListRow()

            if calendarService.settings.isEnabled && calendarService.hasWriteAccessOrBetter {
                Section("Default Calendar") {
                    if calendarService.hasFullAccess {
                        if calendars.isEmpty && !hasLoadedCalendars {
                            ProgressView()
                                .onAppear(perform: loadCalendars)
                        } else {
                            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                Button(action: {
                                    selectCalendar(calendar)
                                }) {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color(calendar.cgColor))
                                            .frame(width: 14, height: 14)
                                        Text(calendar.title)
                                            .font(.obsidianBody)
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        if calendarService.settings.selectedCalendarIdentifier == calendar.calendarIdentifier {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.electricViolet)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full Access required to choose a calendar.")
                                .font(.obsidianBody)
                                .foregroundColor(.textPrimary)
                            Text("Currently saving to system default.")
                                .foregroundColor(.textSecondary)
                                .font(.obsidianFootnote)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(ObsidianSecondaryButtonStyle())
                        }
                    }
                }
                .textCase(nil)
                .obsidianListRow()

                Section("Default Alerts") {
                    ForEach(AppointmentReminderTime.allCases, id: \.rawValue) { option in
                        Toggle(option.displayName, isOn: Binding(
                            get: { calendarService.settings.alertOffsets.contains(option) },
                            set: { isOn in
                                updateCalendarSettings { settings in
                                    if isOn {
                                        if !settings.alertOffsets.contains(option) {
                                            settings.alertOffsets.append(option)
                                        }
                                    } else {
                                        settings.alertOffsets.removeAll { $0 == option }
                                    }
                                }
                            }
                        ))
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                    }
                    Text("These alerts are saved inside Apple Calendar events.")
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                }
                .textCase(nil)
                .obsidianListRow()
            }
        }
        .navigationTitle("Calendar Settings")
        .obsidianInlineNavigation()
        .obsidianListScreen()
        .alert("Calendar Access Denied", isPresented: $showDeniedAlert) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Please enable Calendar permissions in Settings to save events.")
        }
        .alert("Calendar settings not saved", isPresented: Binding(
            get: { settingsErrorMessage != nil },
            set: { if !$0 { settingsErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { settingsErrorMessage = nil }
        } message: {
            Text(settingsErrorMessage ?? "Calendar settings were not saved.")
        }
    }

    private func loadCalendars() {
        if calendarService.hasFullAccess {
            calendars = calendarService.allEventCalendars()
        } else {
            calendars = []
        }
        hasLoadedCalendars = true
    }

    private func requestAccess() {
        calendarService.requestAccessIfNeeded { granted in
            if granted {
                loadCalendars()
            } else {
                showDeniedAlert = true
            }
        }
    }

    private func selectCalendar(_ calendar: EKCalendar) {
        calendarService.setSelectedCalendar(calendar)
        if let message = calendarService.lastErrorMessage {
            settingsErrorMessage = message
        }
    }

    private func updateCalendarSettings(_ update: (inout CalendarIntegrationSettings) -> Void) {
        var updated = calendarService.settings
        update(&updated)

        guard calendarService.updateSettings(updated) else {
            settingsErrorMessage = calendarService.lastErrorMessage ?? "Calendar settings were not saved."
            return
        }
    }
}

private extension Color {
    init(_ cgColor: CGColor?) {
        if let cgColor = cgColor {
            self = Color(UIColor(cgColor: cgColor))
        } else {
            self = .gray
        }
    }
}
