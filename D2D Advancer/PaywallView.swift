import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var paywallManager = PaywallManager.shared
    @State private var selectedPlan: PaywallManager.SubscriptionPlan = PaywallManager.shared.defaultPlan
    @State private var showingSampleWorkspace = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.obsidianBackground(for: colorScheme)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    headerSection
                    planSection
                    includedSection
                    sampleWorkspaceButton

                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
            }
            .accessibilityIdentifier("paywallScreen")

            topBar
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .background(Color.obsidianBackground(for: colorScheme))
                .zIndex(1)
        }
        .safeAreaInset(edge: .bottom) {
            purchaseBar
        }
        .onChangeCompat(of: paywallManager.offering) { _ in
            selectedPlan = paywallManager.defaultPlan
        }
        .fullScreenCover(isPresented: $showingSampleWorkspace) {
            SubscriptionSampleWorkspaceView(offering: paywallManager.offering)
        }
        .onAppear {
            selectedPlan = paywallManager.defaultPlan
            if paywallManager.products.isEmpty {
                Task {
                    await paywallManager.loadProducts()
                }
            }
        }
    }

    // MARK: - Main Layout

    private var topBar: some View {
        HStack {
            Capsule()
                .fill(Color.obsidianBorder.opacity(0.75))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close paywall",
                accentColor: Color.textSecondary,
                backgroundColor: Color.obsidianSurface,
                foregroundColor: Color.textSecondary,
                borderColor: Color.obsidianBorder.opacity(0.7)
            ) {
                dismiss()
            }
            .accessibilityIdentifier("paywallCloseButton")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.obsidianSmall)
                    .foregroundColor(.electricViolet)
                    .frame(width: 30, height: 30)
                    .background(Color.electricViolet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(paywallManager.offering == .team ? "D2D Advancer Team" : "D2D Advancer Pro")
                    .font(.obsidianSmall)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(cleanHeroTitle)
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    paywallManager.offering == .team
                        ? "One owner and two workers share assigned leads, service jobs, and on-duty location tools."
                        : "Unlimited leads, iCloud backup, reminders, and field tools in one focused workspace."
                )
                    .font(.obsidianBody)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedPlanCaption: String {
        paywallManager.purchaseCaption(for: selectedPlan)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a plan")
                .font(.obsidianSubheadline)
                .foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(orderedPlans, id: \.self) { plan in
                    planButton(for: plan)
                }
            }
        }
    }

    private var orderedPlans: [PaywallManager.SubscriptionPlan] {
        paywallManager.visiblePlans
    }

    private func planButton(for plan: PaywallManager.SubscriptionPlan) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedPlan = plan
            }
        } label: {
            planRow(for: plan)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(planAccessibilityIdentifier(plan))
    }

    private func planRow(for plan: PaywallManager.SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let hasLoadedProduct = paywallManager.product(for: plan) != nil

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.textPrimary : Color.obsidianBorder, lineWidth: 1.6)
                    .frame(width: 24, height: 24)

                if isSelected {
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(paywallManager.planTitle(plan))
                        .font(.obsidianTitle)
                        .foregroundColor(.textPrimary)

                    Text(planBadge(for: plan))
                        .font(.nano)
                        .foregroundColor(isSelected ? .obsidianBlack : .textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.textPrimary : Color.obsidianElevated)
                        )
                }

                Text(
                    planDescription(for: plan)
                )
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(paywallManager.displayPrice(for: plan))
                    .font(.obsidianHeadline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(hasLoadedProduct ? paywallManager.planPeriod(plan) : "from App Store")
                    .font(.obsidianSmall)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.textPrimary.opacity(0.85) : Color.obsidianBorder.opacity(0.75), lineWidth: isSelected ? 1.4 : 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func planBadge(for plan: PaywallManager.SubscriptionPlan) -> String {
        if let duration = paywallManager.eligibleTrialDuration(for: plan) {
            return "\(duration.capitalized) free"
        }
        return plan == .yearly || plan == .teamYearly ? "Best value" : "Flexible"
    }

    private func planDescription(for plan: PaywallManager.SubscriptionPlan) -> String {
        if let duration = paywallManager.eligibleTrialDuration(for: plan) {
            return "Try it free for \(duration), then keep the lowest annual cost."
        }
        return plan == .yearly || plan == .teamYearly
            ? "Lowest cost for ongoing field work."
            : "Pay month to month with the same access."
    }

    private var includedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Included")
                .font(.obsidianSubheadline)
                .foregroundColor(.textPrimary)

            VStack(spacing: 12) {
                ForEach(Array(cleanBenefits.enumerated()), id: \.offset) { _, benefit in
                    benefitRow(
                        icon: benefit.icon,
                        title: benefit.title,
                        subtitle: benefit.subtitle,
                        color: benefit.color
                    )
                }
            }
        }
    }

    private var cleanBenefits: [(icon: String, title: String, subtitle: String, color: Color)] {
        if paywallManager.offering == .team {
            return [
                ("person.3.fill", "Three seats included", "One owner plus two sales reps or technicians.", .statusConverted),
                ("person.crop.circle.badge.checkmark", "Assigned work only", "Workers see only the leads and jobs assigned to them.", .statusInterested),
                ("calendar.badge.clock", "Shared jobs", "Send sold work to technicians with arrival windows and details.", .statusNotHome),
                ("location.fill", "On-duty locations", "Share live location only while a member is manually on duty.", .electricViolet)
            ]
        }
        return [
            ("person.text.rectangle.fill", "Unlimited leads", "Keep every door, note, status, and follow-up.", .statusConverted),
            ("icloud.fill", "iCloud backup", "Sync through the Apple ID already on the device.", .statusInterested),
            ("bell.badge.fill", "Smart reminders", "Stay on top of callbacks and appointments.", .statusNotHome),
            ("map.fill", "Field tools", "Plan routes, search areas, and work from the map.", .electricViolet)
        ]
    }

    private var sampleWorkspaceButton: some View {
        Button {
            showingSampleWorkspace = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .foregroundColor(.electricViolet)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore Sample Workspace")
                        .font(.obsidianTitle)
                    Text("Sample data • Read only")
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ObsidianSecondaryButtonStyle())
        .accessibilityIdentifier("paywallSampleWorkspaceButton")
    }

    private func benefitRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.obsidianFootnote)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                )
        )
    }

    private var cleanHeroTitle: String {
        paywallManager.offering == .team
            ? "Run the crew from one workspace."
            : "Upgrade your field workflow."
    }

    private func planAccessibilityIdentifier(_ plan: PaywallManager.SubscriptionPlan) -> String {
        switch plan {
        case .weekly: return "paywallPlanWeeklyButton"
        case .monthly: return "paywallPlanMonthlyButton"
        case .yearly: return "paywallPlanYearlyButton"
        case .teamMonthly: return "paywallPlanTeamMonthlyButton"
        case .teamYearly: return "paywallPlanTeamYearlyButton"
        }
    }

    // MARK: - Purchase Bar

    private var purchaseBar: some View {
        VStack(spacing: 0) {
            Color.obsidianBorder.opacity(0.45)
                .frame(height: 0.5)

            VStack(spacing: 11) {
                purchaseStatusBanner

                Button(action: {
                    subscribe()
                }) {
                    HStack(spacing: 10) {
                        if paywallManager.isPurchasing || paywallManager.isLoadingProducts {
                            ProgressView()
                                .tint(.obsidianBlack)
                            Text(paywallManager.isLoadingProducts ? "Loading plans..." : "Processing...")
                                .font(.obsidianTitle)
                        } else {
                            Image(systemName: purchaseButtonIcon)
                                .font(.obsidianAction)

                            VStack(spacing: 2) {
                                Text(purchaseButtonTitle)
                                    .font(.obsidianTitle)

                                Text(purchaseButtonSubtitle)
                                    .font(.micro)
                                    .opacity(0.85)
                            }
                        }
                    }
                    .foregroundColor(Color.obsidianBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(paywallManager.isPurchasing || paywallManager.isLoadingProducts)
                .accessibilityIdentifier("paywallPurchaseButton")

                HStack(spacing: 14) {
                    Button("Restore Purchases") {
                        restorePurchases()
                    }
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .disabled(paywallManager.isPurchasing)
                    .accessibilityIdentifier("paywallRestoreButton")

                    Text("•")
                        .font(.nano)
                        .foregroundColor(.textMuted)

                    Button(action: { openPrivacyPolicy() }) {
                        Text("Privacy")
                            .font(.obsidianCaption)
                            .foregroundColor(.textSecondary)
                    }
                    .accessibilityIdentifier("paywallPrivacyButton")

                    Button(action: { openTermsOfUse() }) {
                        Text("Terms")
                            .font(.obsidianCaption)
                            .foregroundColor(.textSecondary)
                    }
                    .accessibilityIdentifier("paywallTermsButton")
                }

                Text(paywallManager.renewalDisclosure(for: selectedPlan))
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(
                Color.obsidianBackground(for: colorScheme)
                    .opacity(0.96)
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                Rectangle()
                    .fill(Color.obsidianBorder.opacity(0.5))
                    .frame(height: 1),
                alignment: .top
            )
        }
    }

    @ViewBuilder
    private var purchaseStatusBanner: some View {
        if let message = paywallManager.purchaseStatusMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: paywallManager.purchaseStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.obsidianFootnote)
                    .foregroundColor(paywallManager.purchaseStatusIsError ? .statusNotHome : .statusInterested)

                Text(message)
                    .font(.obsidianCaption)
                    .foregroundColor(.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                (paywallManager.purchaseStatusIsError ? Color.statusNotHome : Color.statusInterested).opacity(0.35),
                                lineWidth: 0.75
                            )
                    )
            )
            .accessibilityIdentifier("paywallPurchaseStatusBanner")
        }
    }

    private var purchaseButtonTitle: String {
        if paywallManager.product(for: selectedPlan) == nil {
            return "Retry Loading Plans"
        }
        if let trialTitle = paywallManager.trialButtonTitle(for: selectedPlan) {
            return trialTitle
        }
        return paywallManager.offering == .team ? "Continue with Team" : "Continue with Pro"
    }

    private var purchaseButtonSubtitle: String {
        if paywallManager.product(for: selectedPlan) == nil {
            return "We'll reconnect to the App Store"
        }
        return selectedPlanCaption
    }

    private var purchaseButtonIcon: String {
        if paywallManager.product(for: selectedPlan) == nil {
            return "arrow.clockwise"
        }
        return paywallManager.offering == .team ? "person.3.fill" : "crown.fill"
    }

    // MARK: - Actions

    private func subscribe() {
        Task {
            await paywallManager.purchase(plan: selectedPlan)
            let purchaseIsActive = selectedPlan.isTeamPlan
                ? paywallManager.hasVerifiedTeamBillingEntitlement
                : paywallManager.isPremium
            if purchaseIsActive {
                dismiss()
            }
        }
    }

    private func restorePurchases() {
        Task {
            await paywallManager.restorePurchases()
            let purchaseIsActive = paywallManager.offering == .team
                ? paywallManager.hasVerifiedTeamBillingEntitlement
                : paywallManager.isPremium
            if purchaseIsActive {
                dismiss()
            }
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://dan1sl6nd.github.io/D2D-Advancer/PRIVACY_POLICY.html") {
            UIApplication.shared.open(url)
        }
    }

    private func openTermsOfUse() {
        if let url = URL(string: "https://dan1sl6nd.github.io/D2D-Advancer/TERMS_OF_USE.html") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    PaywallView()
}
