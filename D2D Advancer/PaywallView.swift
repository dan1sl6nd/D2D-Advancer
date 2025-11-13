import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var paywallManager = PaywallManager.shared
    @State private var selectedPlan: PaywallManager.SubscriptionPlan = PaywallManager.shared.experience.recommendedPlan

    var isAtLimit: Bool {
        paywallManager.remainingFreeLeads() == 0 && !paywallManager.isPremium
    }

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    headerSection
                        .padding(.top, 20)

                    // Pricing Section
                    pricingSection

                    // Benefits
                    benefitsSection

                    // Social Proof
                    socialProofSection

                    // Testimonials
                    testimonialsSection

                    // FAQ
                    faqSection

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            floatingPurchaseButton
        }
        .onChangeCompat(of: paywallManager.experience.recommendedPlan) { newPlan in
            selectedPlan = newPlan
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 20) {
            // Modern Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "house.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(spacing: 10) {
                Text("Choose Your Plan")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Unlock Your Full Potential")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.9), Color.purple.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Unlimited leads • Advanced tools • Premium support")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 16) {
            // Weekly Plan (Featured with Trial)
            ModernPricingCard(
                badge: "3-DAY FREE TRIAL",
                badgeGradient: [Color.orange, Color.red],
                title: "Weekly",
                price: "$9.99",
                period: "per week",
                subtitle: "Try free for 3 days",
                features: ["Cancel anytime during trial", "Then $9.99/week"],
                isSelected: selectedPlan == .weekly,
                isPopular: true
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedPlan = .weekly
                }
            }

            // Yearly Plan
            ModernPricingCard(
                badge: "BEST VALUE",
                badgeGradient: [Color.green, Color.blue],
                title: "Yearly",
                price: "$36.99",
                period: "per year",
                subtitle: "Only $3.08/month",
                features: ["Save 93% vs weekly", "Best value option"],
                isSelected: selectedPlan == .yearly,
                isPopular: false
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedPlan = .yearly
                }
            }
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(spacing: 16) {
            Text("What's Included")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ModernBenefitRow(icon: "infinity.circle.fill", title: "Unlimited Leads", color: .blue)
                ModernBenefitRow(icon: "map.circle.fill", title: "Advanced Mapping", color: .green)
                ModernBenefitRow(icon: "bell.badge.fill", title: "Smart Follow-ups", color: .orange)
                ModernBenefitRow(icon: "crown.fill", title: "Premium Support", color: .purple)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    // MARK: - Social Proof Section

    private var socialProofSection: some View {
        let tagline = paywallManager.experience.socialProofTagline

        return VStack(spacing: 16) {
            // Rating display
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }

                HStack(spacing: 8) {
                    Text("4.9")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("out of 5")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }

                Text("average rating")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.2), Color.orange.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )

            Text(tagline)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    // MARK: - Testimonials Section

    private var testimonialsSection: some View {
        let testimonials = paywallManager.experience.testimonials

        return VStack(spacing: 16) {
            Text("What Users Say")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ForEach(testimonials) { testimonial in
                    ModernTestimonialCard(
                        avatar: testimonial.avatar,
                        name: testimonial.name,
                        quote: testimonial.quote
                    )
                }
            }
        }
    }

    // MARK: - FAQ Section

    private var faqSection: some View {
        let items = paywallManager.experience.faqItems

        return VStack(spacing: 16) {
            Text("Common Questions")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ForEach(items) { faq in
                    ModernFAQRow(question: faq.question, answer: faq.answer)
                }
            }
        }
    }

    // MARK: - Floating Purchase Button

    private var floatingPurchaseButton: some View {
        VStack(spacing: 0) {
            // Subtle top divider
            LinearGradient(
                colors: [Color.white.opacity(0.1), Color.white.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1)

            VStack(spacing: 14) {
                // CTA Button
                Button(action: {
                    subscribe()
                }) {
                    HStack(spacing: 10) {
                        if paywallManager.isPurchasing {
                            ProgressView()
                                .tint(.white)
                            Text("Processing...")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        } else {
                            if selectedPlan == .weekly {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Start 3-Day Free Trial")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                            } else {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Subscribe Now")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: selectedPlan == .weekly
                                ? [Color.orange, Color.red]
                                : [Color.green, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: (selectedPlan == .weekly ? Color.orange : Color.green).opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(paywallManager.isPurchasing)

                // Restore button
                Button("Restore Purchases") {
                    restorePurchases()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))

                // Legal info
                VStack(spacing: 6) {
                    if selectedPlan == .weekly {
                        Text("Free for 3 days • Then $9.99/week • Cancel anytime")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("$36.99/year • Cancel anytime")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    HStack(spacing: 8) {
                        Button(action: { openPrivacyPolicy() }) {
                            Text("Privacy")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Text("•").foregroundColor(.white.opacity(0.3)).font(.system(size: 8))
                        Button(action: { openTermsOfUse() }) {
                            Text("Terms")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                Color(red: 0.08, green: 0.08, blue: 0.12)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.03), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
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
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: badgeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
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
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(period)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Subtitle
            Text(subtitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(badgeGradient.first)

                        Text(feature)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
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
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: isSelected ? badgeGradient.first!.opacity(0.3) : Color.clear,
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
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
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)

            // Author
            HStack(spacing: 10) {
                Text(avatar)
                    .font(.system(size: 24))

                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                // Star rating
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            if isExpanded {
                Text(answer)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isExpanded ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isExpanded
                                ? LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.05)],
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
                .fill(isSelected ? Color.orange : Color.clear)
                .stroke(isSelected ? Color.orange : Color.white.opacity(0.3), lineWidth: 2)
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
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor)
                        .cornerRadius(4)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let originalPrice = originalPrice {
                            Text(originalPrice)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .strikethrough()
                        }

                        Text(price)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isSelected ? 0.15 : 0.08))
                .stroke(isSelected ? Color.orange : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
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
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
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
                .font(.system(size: 32))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white)
                    .italic()

                HStack {
                    Text(name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    HStack(spacing: 2) {
                        ForEach(0..<rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 10))
                        }
                    }
                }
            }

            Spacer()
        }
        .glassCard(padding: 12)
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
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 12))
                }
                .padding()
            }

            if isExpanded {
                Text(answer)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)
                    .padding(.bottom)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard(padding: 0)
    }
}

// Glass Card Modifier
extension View {
    func glassCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

#Preview {
    PaywallView()
}
