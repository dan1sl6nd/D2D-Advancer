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
            // Gradient background
            LinearGradient(
                colors: [Color.blue, Color.purple, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerSection

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

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
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
        let experience = paywallManager.experience

        return VStack(spacing: 24) {
            // App Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 110, height: 110)

                Image(systemName: "house.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.white)
            }

            VStack(spacing: 12) {
                Text(isAtLimit ? "Unlock Premium Features" : experience.heroTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(experience.heroHighlight)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Color.yellow)

                Text(isAtLimit ? "You've reached the free plan limit. Upgrade to premium to unlock unlimited leads and advanced features" : experience.heroDescription)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        return VStack(spacing: 12) {
            // Yearly Plan
            SimplePricingCard(
                badge: "BEST VALUE",
                badgeColor: Color.green,
                title: "Yearly Plan",
                price: "$36.99/year",
                originalPrice: "$519.48",
                subtitle: "Save 93% • Only $3.08/month",
                isSelected: selectedPlan == .yearly
            )
            .onTapGesture {
                selectedPlan = .yearly
            }

            // Weekly Plan
            SimplePricingCard(
                badge: "3-DAY FREE TRIAL",
                badgeColor: Color.orange,
                title: "Weekly Plan",
                price: "$9.99/week",
                originalPrice: nil,
                subtitle: "3 days free, then $9.99/week • Cancel anytime",
                isSelected: selectedPlan == .weekly
            )
            .onTapGesture {
                selectedPlan = .weekly
            }
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        let benefits = paywallManager.experience.benefits

        return VStack(spacing: 16) {
            Text("Everything You Need")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(benefits) { benefit in
                    BenefitRow(icon: benefit.icon, title: benefit.title, subtitle: benefit.subtitle)
                }
            }
        }.glassCard(padding: 24)
    }

    // MARK: - Social Proof Section

    private var socialProofSection: some View {
        let tagline = paywallManager.experience.socialProofTagline

        return VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 16))
                    }
                }

                Text("4.9")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("average rating")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .glassCard(padding: 16)

            Text(tagline)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Testimonials Section

    private var testimonialsSection: some View {
        let testimonials = paywallManager.experience.testimonials

        return VStack(spacing: 12) {
            Text("Success Stories")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                ForEach(testimonials) { testimonial in
                    TestimonialCard(
                        avatar: testimonial.avatar,
                        name: testimonial.name,
                        rating: 5,
                        text: testimonial.quote
                    )
                }
            }
        }
    }

    // MARK: - FAQ Section

    private var faqSection: some View {
        let items = paywallManager.experience.faqItems

        return VStack(spacing: 12) {
            Text("Frequently Asked Questions")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                ForEach(items) { faq in
                    FAQRow(question: faq.question, answer: faq.answer)
                }
            }
        }
    }

    // MARK: - Floating Purchase Button

    private var floatingPurchaseButton: some View {
        VStack(spacing: 12) {
            // REQUIRED SUBSCRIPTION INFORMATION - Apple Guideline 3.1.2
            VStack(spacing: 8) {
                Text("D2D Advancer Premium Subscription")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                if selectedPlan == .weekly {
                    Text("Weekly Plan: 3 days free, then $9.99 per week")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    Text("Yearly Plan: $36.99 per year (equivalent to $3.08/month)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }

                Text("Subscription includes unlimited lead management, advanced mapping features, automated follow-ups, and premium support.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.bottom, 8)

            Button(action: {
                subscribe()
            }) {
                HStack {
                    if paywallManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                        Text("Processing...")
                    } else {
                        VStack(spacing: 4) {
                            Text(selectedPlan == .weekly ? "Start 3-Day Free Trial" : "Subscribe for $36.99/year")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text(selectedPlan == .weekly ? "Then $9.99/week • Cancel anytime" : "Save 93% • Cancel anytime")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(28)
            }
            .disabled(paywallManager.isPurchasing)

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    restorePurchases()
                }
                .foregroundColor(.white.opacity(0.75))
                .font(.system(size: 12, design: .rounded))

                if !isAtLimit {
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))

                    Button("Continue with Free") {
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.75))
                    .font(.system(size: 12, design: .rounded))
                }
            }

            Text("Payment charged to Apple ID at purchase confirmation. Auto-renews unless canceled at least 24 hours before period ends. Manage subscriptions in your Apple ID Account Settings.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            HStack(spacing: 16) {
                Button(action: {
                    openPrivacyPolicy()
                }) {
                    Text("Privacy Policy")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .underline()
                }

                Text("•")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 11))

                Button(action: {
                    openTermsOfUse()
                }) {
                    Text("Terms of Use (EULA)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .underline()
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack(alignment: .top) {
                Color.clear
                    .background(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.5)
            }
        )
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

// MARK: - Supporting Components

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
