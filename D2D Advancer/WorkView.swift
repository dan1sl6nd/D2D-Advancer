import SwiftUI
import CoreData

struct WorkView: View {
    let roleContext: TeamRoleContext

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    @ObservedObject private var teamService = TeamFirebaseService.shared
    @State private var showingScheduleView = false
    @State private var selectedLead: Lead?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: true)],
        predicate: Lead.Status.activeFollowUpPredicate,
        animation: .default
    ) private var followUpLeads: FetchedResults<Lead>

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.obsidianBackground(for: colorScheme))
                        .frame(height: ObsidianLayout.safeAreaTop(geometry))

                    ObsidianHeaderView(
                        roleContext.workScreenTitle,
                        titleAccessibilityIdentifier: "workScreen"
                    ) {
                        if router.selectedWorkSection == .schedule && roleContext != .technician {
                            ObsidianCompactIconButton(
                                icon: "plus",
                                accessibilityLabel: roleContext.workScheduleActionTitle,
                                accessibilityIdentifier: "appointmentsScheduleButton",
                                size: 44
                            ) {
                                guard paywallManager.gateAction() else { return }
                                showingScheduleView = true
                            }
                        }
                    }

                    if roleContext != .technician {
                        sectionControl
                    }

                    if overdueFollowUpCount > 0 || todayJobCount > 0 {
                        todayWorkStrip
                    }

                    Group {
                        if router.selectedWorkSection == .followUps {
                            FollowUpView(isEmbeddedInWork: true)
                        } else {
                            AppointmentsView(isEmbeddedInWork: true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color.obsidianBackground(for: colorScheme))
            .onAppear {
                if roleContext == .technician {
                    router.selectedWorkSection = .schedule
                }
            }
            .onChange(of: roleContext) { _, newRole in
                if newRole == .technician {
                    router.selectedWorkSection = .schedule
                }
            }
            .sheet(isPresented: $showingScheduleView) {
                SelectLeadForAppointmentView { lead in
                    selectedLead = lead
                    showingScheduleView = false
                }
            }
            .sheet(item: $selectedLead) { lead in
                ScheduleAppointmentView(lead: lead)
            }
        }
    }

    private var sectionControl: some View {
        HStack(spacing: 4) {
            sectionButton(
                .followUps,
                title: "Follow-ups",
                icon: "bell"
            )
            sectionButton(
                .schedule,
                title: roleContext.workScheduleSectionTitle,
                icon: "calendar"
            )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.obsidianSurface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color.obsidianBackground(for: colorScheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Work sections")
    }

    private var todayWorkStrip: some View {
        HStack(spacing: 8) {
            if roleContext != .technician && overdueFollowUpCount > 0 {
                todayWorkButton(
                    value: overdueFollowUpCount,
                    title: "Overdue",
                    icon: "bell.badge.fill",
                    color: Color.statusNotHome
                ) {
                    router.selectedWorkSection = .followUps
                }
            }

            if todayJobCount > 0 {
                todayWorkButton(
                    value: todayJobCount,
                    title: roleContext == .technician ? "Jobs today" : "Today",
                    icon: "calendar.badge.clock",
                    color: Color.electricViolet
                ) {
                    router.selectedWorkSection = .schedule
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color.obsidianBackground(for: colorScheme))
        .accessibilityIdentifier("workTodaySummary")
    }

    private func todayWorkButton(
        value: Int,
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                Text("\(value)")
                    .font(.obsidianCallout)
                Text(title)
                    .font(.obsidianFootnote)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.micro)
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var overdueFollowUpCount: Int {
        let now = Date()
        let personal = followUpLeads.filter { ($0.followUpDate ?? .distantFuture) <= now }.count
        guard let member = teamService.currentMember else { return personal }
        let team = teamService.teamLeads.filter { lead in
            guard lead.assignedToUserId == member.userId,
                  let date = lead.followUpDate,
                  date <= now else { return false }
            return lead.status.allowsFollowUpWorkflow && lead.status != .booked
        }.count
        return personal + team
    }

    private var todayJobCount: Int {
        let calendar = Calendar.current
        let personal = appointmentManager.appointments.filter {
            calendar.isDateInToday($0.startDate)
                && $0.status != .completed
                && $0.status != .cancelled
        }.count

        guard let member = teamService.currentMember else { return personal }
        let team = teamService.teamBookings.filter { booking in
            let isVisible = member.role == .owner || booking.assignedToUserId == member.userId
            return isVisible
                && calendar.isDateInToday(booking.startDate)
                && booking.status != .completed
                && booking.status != .cancelled
        }.count
        return personal + team
    }

    private func sectionButton(
        _ section: WorkTabSection,
        title: String,
        icon: String
    ) -> some View {
        let isSelected = router.selectedWorkSection == section

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                router.selectedWorkSection = section
            }
        } label: {
            Label(title, systemImage: isSelected ? "\(icon).fill" : icon)
                .font(.obsidianFootnote)
                .foregroundColor(isSelected ? .white : .textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.electricViolet : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workSection_\(section.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
