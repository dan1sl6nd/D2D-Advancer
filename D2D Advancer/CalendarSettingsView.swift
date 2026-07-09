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
        ScrollView {
            LazyVStack(spacing: 16) {
                ObsidianScreenTitle(
                    title: "Calendar Settings",
                    subtitle: "Send scheduled appointments to Apple Calendar.",
                    icon: "calendar"
                )

                appleCalendarSection

                if calendarService.settings.isEnabled && calendarService.hasWriteAccessOrBetter {
                    defaultCalendarSection
                    defaultAlertsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .obsidianScreenBackground()
        .obsidianPushedNavigation("Calendar Settings", backButtonAccessibilityIdentifier: "calendarSettingsBackButton")
        .onAppear {
            if calendarService.settings.isEnabled && calendarService.hasFullAccess {
                loadCalendars()
            }
        }
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

    private var appleCalendarSection: some View {
        MoreSectionGroup(
            title: "Apple Calendar",
            icon: "calendar.badge.plus",
            subtitle: "Keep customer appointments visible outside the app.",
            accentColor: Color.electricViolet
        ) {
            MoreCardView(
                icon: "calendar",
                iconColor: Color.electricViolet,
                title: "Calendar Sync",
                subtitle: calendarService.settings.isEnabled ? "Appointments are sent to Apple Calendar" : "Appointments stay inside D2D Advancer",
                trailingContent: {
                    Toggle("Add appointments to Apple Calendar", isOn: Binding(
                        get: { calendarService.settings.isEnabled },
                        set: { isEnabled in
                            updateCalendarSettings { settings in
                                settings.isEnabled = isEnabled
                            }

                            if isEnabled && calendarService.hasFullAccess {
                                loadCalendars()
                            }
                        }
                    ))
                    .labelsHidden()
                    .accessibilityIdentifier("calendarSettingsEnableToggle")
                }
            )

            if !calendarService.hasWriteAccessOrBetter {
                calendarDivider

                MoreCardView(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: Color.statusNotHome,
                    title: "Calendar Access",
                    subtitle: "Required to sync appointments",
                    trailingContent: {
                        Button("Allow") {
                            requestAccess()
                        }
                        .buttonStyle(ObsidianSecondaryButtonStyle())
                    }
                )
            }
        }
    }

    private var defaultCalendarSection: some View {
        MoreSectionGroup(
            title: "Default Calendar",
            icon: "calendar.circle.fill",
            subtitle: "Choose where new appointment events are saved.",
            accentColor: Color.statusInterested
        ) {
            if calendarService.hasFullAccess {
                if calendars.isEmpty && !hasLoadedCalendars {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.electricViolet)

                        Text("Loading calendars...")
                            .font(.obsidianBody)
                            .foregroundColor(Color.textSecondary)

                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .onAppear(perform: loadCalendars)
                } else if calendars.isEmpty {
                    MoreCardView(
                        icon: "calendar.badge.exclamationmark",
                        iconColor: Color.statusNotHome,
                        title: "No Calendars Found",
                        subtitle: "Create an Apple Calendar first, then return here"
                    )
                } else {
                    ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                        if index > 0 {
                            calendarDivider
                        }

                        calendarButton(calendar)
                    }
                }
            } else {
                MoreCardView(
                    icon: "lock.fill",
                    iconColor: Color.statusNotHome,
                    title: "Full Access Required",
                    subtitle: "The app is currently saving to the system default calendar",
                    trailingContent: {
                        Button("Settings") {
                            openAppSettings()
                        }
                        .buttonStyle(ObsidianSecondaryButtonStyle())
                    }
                )
            }
        }
    }

    private var defaultAlertsSection: some View {
        MoreSectionGroup(
            title: "Default Alerts",
            icon: "bell.badge.fill",
            subtitle: "These alerts are saved inside Apple Calendar events.",
            accentColor: Color.statusNotHome
        ) {
            ForEach(Array(AppointmentReminderTime.allCases.enumerated()), id: \.element.rawValue) { index, option in
                if index > 0 {
                    calendarDivider
                }

                MoreCardView(
                    icon: "bell.fill",
                    iconColor: Color.statusNotHome,
                    title: option.displayName,
                    subtitle: "Before appointment start",
                    trailingContent: {
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
                        .labelsHidden()
                    }
                )
            }
        }
    }

    private var calendarDivider: some View {
        Rectangle()
            .fill(Color.obsidianBorder.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private func calendarButton(_ calendar: EKCalendar) -> some View {
        Button {
            selectCalendar(calendar)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(calendar.cgColor))
                        .frame(width: 14, height: 14)
                }
                .frame(width: 42, height: 42)
                .background(Color(calendar.cgColor).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(calendar.title)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(calendar.source.title)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if calendarService.settings.selectedCalendarIdentifier == calendar.calendarIdentifier {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.electricViolet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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
