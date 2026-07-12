import SwiftUI

struct WorkView: View {
    let roleContext: TeamRoleContext

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var showingScheduleView = false
    @State private var selectedLead: Lead?

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
                        if router.selectedWorkSection == .schedule {
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

                    sectionControl

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
