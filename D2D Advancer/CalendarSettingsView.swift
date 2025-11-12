import SwiftUI
import EventKit
import UIKit

struct CalendarSettingsView: View {
    @ObservedObject private var calendarService = CalendarService.shared

    @State private var calendars: [EKCalendar] = []
    @State private var hasLoadedCalendars = false
    @State private var showDeniedAlert = false

    var body: some View {
        List {
            Section("Apple Calendar") {
                Toggle("Add appointments to Apple Calendar", isOn: Binding(
                    get: { calendarService.settings.isEnabled },
                    set: { calendarService.settings.isEnabled = $0 }
                ))

                if !calendarService.hasWriteAccessOrBetter {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Calendar access not granted")
                        Spacer()
                        Button("Allow") { requestAccess() }
                    }
                }
            }

            if calendarService.settings.isEnabled && calendarService.hasWriteAccessOrBetter {
                Section("Default Calendar") {
                    if calendarService.hasFullAccess {
                        if calendars.isEmpty && !hasLoadedCalendars {
                            ProgressView()
                                .onAppear(perform: loadCalendars)
                        } else {
                            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                Button(action: {
                                    calendarService.setSelectedCalendar(calendar)
                                }) {
                                    HStack {
                                        Circle()
                                            .fill(Color(calendar.cgColor))
                                            .frame(width: 14, height: 14)
                                        Text(calendar.title)
                                        Spacer()
                                        if calendarService.settings.selectedCalendarIdentifier == calendar.calendarIdentifier {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full Access required to choose a calendar.")
                            Text("Currently saving to system default.")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                }

                Section("Default Alerts") {
                    ForEach(AppointmentReminderTime.allCases, id: \.rawValue) { option in
                        Toggle(option.displayName, isOn: Binding(
                            get: { calendarService.settings.alertOffsets.contains(option) },
                            set: { isOn in
                                if isOn {
                                    if !calendarService.settings.alertOffsets.contains(option) {
                                        calendarService.settings.alertOffsets.append(option)
                                    }
                                } else {
                                    calendarService.settings.alertOffsets.removeAll { $0 == option }
                                }
                            }
                        ))
                    }
                    Text("These alerts are saved inside Apple Calendar events.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Calendar Settings")
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
