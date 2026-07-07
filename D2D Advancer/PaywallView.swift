import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var paywallManager = PaywallManager.shared
    @State private var selectedPlan: PaywallManager.SubscriptionPlan = PaywallManager.shared.experience.recommendedPlan

    var body: some View {
        ZStack(alignment: .top) {
            Color.obsidianBackground(for: colorScheme)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    headerSection
                    planSection
                    includedSection

                    Spacer(minLength: 150)
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
        .onChangeCompat(of: paywallManager.experience.recommendedPlan) { newPlan in
            selectedPlan = newPlan
        }
        .onAppear {
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

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.obsidianFootnote)
                    .foregroundColor(.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Color.obsidianSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.5)
                    )
            }
            .accessibilityLabel("Close paywall")
            .accessibilityIdentifier("paywallCloseButton")
        }
    }

    private var headerSection: some View {
        let experience = paywallManager.experience

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.obsidianSmall)
                    .foregroundColor(.electricViolet)
                    .frame(width: 30, height: 30)
                    .background(Color.electricViolet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("D2D Advancer Pro")
                    .font(.obsidianSmall)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(cleanHeroTitle(for: experience))
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Unlimited leads, iCloud backup, reminders, and field tools in one focused workspace.")
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
        if paywallManager.experience.recommendedPlan == .weekly {
            return [.weekly, .yearly]
        }
        return [.yearly, .weekly]
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
        .accessibilityIdentifier(plan == .weekly ? "paywallPlanWeeklyButton" : "paywallPlanYearlyButton")
    }

    private func planRow(for plan: PaywallManager.SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let isWeekly = plan == .weekly
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
                    Text(isWeekly ? "Weekly" : "Yearly")
                        .font(.obsidianTitle)
                        .foregroundColor(.textPrimary)

                    Text(isWeekly ? "3-day trial" : "Best value")
                        .font(.nano)
                        .foregroundColor(isSelected ? .obsidianBlack : .textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.textPrimary : Color.obsidianElevated)
                        )
                }

                Text(isWeekly ? "Try the full app first." : "Lowest cost for daily field work.")
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

                Text(hasLoadedProduct ? (isWeekly ? "/ week" : "/ year") : "from App Store")
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
        [
            ("person.text.rectangle.fill", "Unlimited leads", "Keep every door, note, status, and follow-up.", .statusConverted),
            ("icloud.fill", "iCloud backup", "Sync through the Apple ID already on the device.", .statusInterested),
            ("bell.badge.fill", "Smart reminders", "Stay on top of callbacks and appointments.", .statusNotHome),
            ("map.fill", "Field tools", "Plan routes, search areas, and work from the map.", .electricViolet)
        ]
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

    private func cleanHeroTitle(for experience: PaywallExperience) -> String {
        switch experience.recommendedPlan {
        case .weekly:
            return "Try Pro in the field."
        case .yearly:
            return "Upgrade your field workflow."
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

                Text(selectedPlan == .weekly ? "No payment required now. Cancel during trial at no charge." : "Full access immediately. Cancel anytime from device settings.")
                    .font(.micro)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .background(Color.obsidianBackground(for: colorScheme).opacity(0.96))
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
        return selectedPlan == .weekly ? "Start Free Trial" : "Continue with Pro"
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
        return selectedPlan == .weekly ? "sparkles" : "crown.fill"
    }

    // MARK: - Actions

    private func subscribe() {
        Task {
            await paywallManager.purchase(plan: selectedPlan)
            if paywallManager.isPremium {
                dismiss()
            }
        }
    }

    private func restorePurchases() {
        Task {
            await paywallManager.restorePurchases()
            if paywallManager.isPremium {
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

// MARK: - Modern Supporting Components

struct PaywallBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.electricViolet.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.electricViolet.opacity(0.32), lineWidth: 0.5)
                )

            Image(systemName: "crown.fill")
                .font(.obsidianSubheadline)
                .foregroundColor(.electricViolet)
        }
    }
}

struct PaywallMetricPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.obsidianCallout)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.micro)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.electricViolet.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PaywallSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.obsidianSubheadline)
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.obsidianCaption)
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.obsidianSubheadline)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.5)
                )
        )
    }
}

struct PaywallProofTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.obsidianFootnote)
                .foregroundColor(.electricViolet)

            Text(value)
                .font(.obsidianCallout)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.micro)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.5)
        )
    }
}

struct CompactPricingCard: View {
    let badge: String
    let badgeGradient: [Color]
    let title: String
    let price: String
    let period: String
    let subtitle: String
    let features: [String]
    let isSelected: Bool
    let isPopular: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(badge)
                    .font(.nano)
                    .foregroundColor(.obsidianBlack)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: badgeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(price)
                        .font(.displayMedium)
                        .foregroundColor(.textPrimary)

                    Text(period)
                        .font(.micro)
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianSmall)
                        .foregroundColor(badgeGradient.first ?? .electricViolet)

                    Text(features.first ?? subtitle)
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(isSelected ? (badgeGradient.first ?? .electricViolet) : Color.obsidianBorder, lineWidth: 1.5)
                    .frame(width: 30, height: 30)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.obsidianBlack)
                        .frame(width: 22, height: 22)
                        .background(badgeGradient.first ?? .electricViolet)
                        .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.obsidianElevated : Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected
                                ? LinearGradient(
                                    colors: badgeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.obsidianElevated, Color.obsidianSurface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: isSelected ? (badgeGradient.first ?? .electricViolet).opacity(0.25) : Color.clear,
                    radius: 12,
                    x: 0,
                    y: 6
                )
        )
    }
}

struct ModernPricingCard: View {
    let badge: String
    let badgeGradient: [Color]
    let title: String
    let price: String
    let period: String
    let subtitle: String
    let features: [String]
    let isSelected: Bool
    let isPopular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Badge
            HStack {
                Text(badge)
                    .font(.nano)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: badgeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.obsidianHeadline)
                        .foregroundStyle(
                            LinearGradient(
                                colors: badgeGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            // Price
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(price)
                    .font(.displayLarge)
                    .foregroundColor(.textPrimary)

                Text(period)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textSecondary)
            }

            // Subtitle
            Text(subtitle)
                .font(.obsidianBody)
                .foregroundColor(.textPrimary)

            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.obsidianFootnote)
                            .foregroundColor(badgeGradient.first)

                        Text(feature)
                            .font(.obsidianCaption)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isSelected ? Color.obsidianElevated : Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isSelected
                                ? LinearGradient(
                                    colors: badgeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.obsidianElevated, Color.obsidianSurface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: isSelected ? (badgeGradient.first ?? .electricViolet).opacity(0.3) : Color.clear,
                    radius: 15,
                    x: 0,
                    y: 8
                )
        )
    }
}

struct ModernBenefitRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.obsidianSubheadline)
                    .foregroundColor(color)
            }

            Text(title)
                .font(.obsidianCallout)
                .foregroundColor(.textPrimary)

            Spacer()

            Image(systemName: "checkmark")
                .font(.obsidianFootnote)
                .foregroundColor(color)
        }
    }
}

struct ModernTestimonialCard: View {
    let avatar: String
    let name: String
    let quote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quote
            Text("\"\(quote)\"")
                .font(.obsidianFootnote)
                .foregroundColor(.textPrimary)
                .lineSpacing(4)

            // Author
            HStack(spacing: 10) {
                Text(avatar)
                    .font(.obsidianHeadline)

                Text(name)
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)

                Spacer()

                // Star rating
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.nano)
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.obsidianBorder, lineWidth: 0.5)
                )
        )
    }
}

struct ModernFAQRow: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.obsidianBody)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.obsidianSmall)
                        .foregroundColor(.textSecondary)
                }
            }

            if isExpanded {
                Text(answer)
                    .font(.obsidianCaption)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isExpanded ? Color.obsidianElevated : Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isExpanded
                                ? LinearGradient(
                                    colors: [Color.electricViolet.opacity(0.3), Color.electricVioletDeep.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.obsidianBorder, Color.obsidianSurface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// Legacy component (kept for compatibility)
struct SimplePricingCard: View {
    let badge: String
    let badgeColor: Color
    let title: String
    let price: String
    let originalPrice: String?
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(isSelected ? Color.electricViolet : Color.clear)
                .stroke(isSelected ? Color.electricViolet : Color.obsidianMuted, lineWidth: 2)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .opacity(isSelected ? 1 : 0)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(badge)
                        .font(.nano)
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor)
                        .cornerRadius(8)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.obsidianAction)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let originalPrice = originalPrice {
                            Text(originalPrice)
                                .font(.obsidianSmall)
                                .foregroundColor(.textSecondary)
                                .strikethrough()
                        }

                        Text(price)
                            .font(.obsidianCallout)
                            .foregroundColor(.textPrimary)
                    }
                }

                Text(subtitle)
                    .font(.obsidianSmall)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.obsidianElevated : Color.obsidianSurface)
                .stroke(isSelected ? Color.electricViolet : Color.obsidianBorder, lineWidth: isSelected ? 1.5 : 0.5)
        )
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.obsidianSubheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.obsidianSmall)
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
    }
}

struct TestimonialCard: View {
    let avatar: String
    let name: String
    let rating: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(avatar)
                .font(.displayLarge)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textPrimary)
                    .italic()

                HStack {
                    Text(name)
                        .font(.obsidianSmall)
                        .foregroundColor(.textPrimary)

                    HStack(spacing: 2) {
                        ForEach(0..<rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.nano)
                        }
                    }
                }
            }

            Spacer()
        }
        .surfaceCard(padding: 12)
    }
}

struct FAQRow: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.obsidianFootnote)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.textSecondary)
                        .font(.obsidianSmall)
                }
                .padding()
            }

            if isExpanded {
                Text(answer)
                    .font(.obsidianSmall)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .surfaceCard(padding: 0)
    }
}

// Surface Card Modifier
extension View {
    func surfaceCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.obsidianBorder, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Premium Lock Overlay

struct PremiumLockOverlay: ViewModifier {
    @ObservedObject private var paywallManager = PaywallManager.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if !paywallManager.isPremium {
                Image(systemName: "lock.fill")
                    .font(.nano)
                    .foregroundColor(.textPrimary)
                    .padding(4)
                    .background(Color.electricViolet)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }
        }
    }
}

extension View {
    func premiumLock() -> some View {
        modifier(PremiumLockOverlay())
    }
}

#Preview {
    PaywallView()
}
