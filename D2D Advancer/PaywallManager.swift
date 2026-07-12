import Foundation
import SwiftUI
import Combine
import StoreKit

struct PaywallExperience {
    struct Benefit: Identifiable, Equatable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    struct Testimonial: Identifiable, Equatable {
        let id = UUID()
        let avatar: String
        let name: String
        let quote: String
    }

    struct FAQ: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let answer: String
    }

    let heroTitle: String
    let heroHighlight: String
    let heroDescription: String
    let socialProofTagline: String
    let benefits: [Benefit]
    let testimonials: [Testimonial]
    let faqItems: [FAQ]
    let recommendedPlan: PaywallManager.SubscriptionPlan

    init(profile: OnboardingProfile?) {
        let profile = profile ?? OnboardingProfile()
        let salesGoal = profile.salesGoal ?? .organizePipeline
        let workflow = profile.workflowStyle ?? .structured
        let focuses = profile.focusAreas.isEmpty
            ? Set(OnboardingProfile.FocusArea.allCases.prefix(3))
            : profile.focusAreas

        self.heroTitle = PaywallExperience.heroTitle(for: salesGoal)
        self.heroHighlight = PaywallExperience.heroHighlight(for: salesGoal)
        self.heroDescription = PaywallExperience.heroDescription(for: salesGoal, workflow: workflow)
        self.socialProofTagline = PaywallExperience.socialProofTagline(for: salesGoal)

        let benefitPriority = PaywallExperience.personalizedBenefits(for: focuses)
        let baseBenefits = PaywallExperience.baseBenefits()
        let mergedBenefits = benefitPriority + baseBenefits.filter { benefit in
            !benefitPriority.contains(where: { $0.title == benefit.title })
        }
        self.benefits = Array(mergedBenefits.prefix(6))

        self.testimonials = PaywallExperience.testimonials(for: salesGoal)
        self.faqItems = PaywallExperience.faq(for: salesGoal)
        // Existing onboarding answers remain decodable, but they no longer steer
        // customers toward the high-churn legacy weekly product.
        self.recommendedPlan = .yearly
    }

    private static func heroTitle(for goal: OnboardingProfile.SalesGoal) -> String {
        switch goal {
        case .organizePipeline: return "Upgrade your command center"
        case .bookMoreAppointments: return "Fill your calendar faster"
        case .territoryPlanning: return "Own your best territory"
        }
    }

    private static func heroHighlight(for goal: OnboardingProfile.SalesGoal) -> String {
        switch goal {
        case .organizePipeline:
            return "Stay on top of every door you've knocked"
        case .bookMoreAppointments:
            return "Turn conversations into confirmed meetings"
        case .territoryPlanning:
            return "Focus on the blocks that close the fastest"
        }
    }

    private static func heroDescription(for goal: OnboardingProfile.SalesGoal, workflow: OnboardingProfile.WorkflowStyle) -> String {
        let workflowSentence: String
        switch workflow {
        case .structured:
            workflowSentence = "Launch each day with a clear plan, pre-built follow-ups, and synced reminders."
        case .hustle:
            workflowSentence = "Capture leads in seconds, drop pins, and fire off next steps without slowing down."
        }

        let goalSentence: String
        switch goal {
        case .organizePipeline:
            goalSentence = "Unlock unlimited lead storage, saved filters, and detailed visit history."
        case .bookMoreAppointments:
            goalSentence = "Unlock appointment tracking, reminders, and confirmations that keep your calendar full."
        case .territoryPlanning:
            goalSentence = "Unlock advanced map layers, neighborhood scores, and saved territories."
        }

        return [goalSentence, workflowSentence].joined(separator: " ")
    }

    private static func socialProofTagline(for goal: OnboardingProfile.SalesGoal) -> String {
        switch goal {
        case .organizePipeline:
            return "Field reps rely on D2D Advancer to keep every conversation organized and searchable."
        case .bookMoreAppointments:
            return "Top setters double their confirmed appointments with streamlined scheduling and reminders."
        case .territoryPlanning:
            return "Door-to-door pros plan smarter routes every morning with D2D territory intelligence."
        }
    }

    private static func personalizedBenefits(for focuses: Set<OnboardingProfile.FocusArea>) -> [Benefit] {
        let orderedFocuses = OnboardingProfile.FocusArea.allCases.filter { focuses.contains($0) }
        return orderedFocuses.map { focus in
            switch focus {
            case .territoryInsights:
                return Benefit(icon: "map.circle.fill", title: "Territory heatmaps", subtitle: "See top streets instantly with demographic overlays and scoring.")
            case .automatedReminders:
                return Benefit(icon: "bolt.badge.clock", title: "Automated reminders", subtitle: "Trigger follow-ups the moment a status changes or a visit is logged.")
            case .leadOrganization:
                return Benefit(icon: "tray.full.fill", title: "Saved lead views", subtitle: "Build custom filters and tabs for every campaign you run.")
            }
        }
    }

    private static func baseBenefits() -> [Benefit] {
        [
            Benefit(icon: "infinity.circle.fill", title: "Unlimited leads", subtitle: "Grow without caps or hidden fees—log every door you knock."),
            Benefit(icon: "icloud.fill", title: "Cloud backup", subtitle: "Sync notes, appointments, and follow-ups across all your devices."),
            Benefit(icon: "bell.badge.fill", title: "Smart nudges", subtitle: "Get gentle reminders before it's time to reconnect with a lead."),
            Benefit(icon: "doc.text.magnifyingglass", title: "Lead history", subtitle: "Review visit notes, outcomes, and attachments in seconds."),
            Benefit(icon: "square.and.pencil", title: "Quick capture", subtitle: "Drop a pin, add photos, and tag motivation while you're still at the door."),
            Benefit(icon: "lock.shield.fill", title: "Secure by design", subtitle: "Your data stays encrypted and backed up automatically.")
        ]
    }

    private static func testimonials(for goal: OnboardingProfile.SalesGoal) -> [Testimonial] {
        switch goal {
        case .organizePipeline:
            return [
                Testimonial(avatar: "🗂️", name: "Riley • Field Rep", quote: "Every lead is organized, searchable, and ready before I knock. No more spreadsheet chaos."),
                Testimonial(avatar: "📋", name: "Jordan • Sales Pro", quote: "Saved views keep my campaigns tidy. I jump from hot leads to follow-ups instantly."),
                Testimonial(avatar: "📱", name: "Alex • Solar Rep", quote: "Notes sync instantly between my phone and iPad. I never lose track of a conversation.")
            ]
        case .bookMoreAppointments:
            return [
                Testimonial(avatar: "📆", name: "Taylor • Setter", quote: "Appointments auto-sync to my calendar and send reminders. Show-up rates shot up immediately."),
                Testimonial(avatar: "🏠", name: "Morgan • Consultant", quote: "I can book, confirm, and follow up on the go without juggling three different apps."),
                Testimonial(avatar: "⏱️", name: "Jamie • Closer", quote: "Same-day slots stay organized and I get nudged if something needs to be rescheduled.")
            ]
        case .territoryPlanning:
            return [
                Testimonial(avatar: "🗺️", name: "Chris • Territory Strategist", quote: "Knowing which areas to focus on saves me hours every week."),
                Testimonial(avatar: "🚪", name: "Lee • Closer", quote: "I cover fewer doors and get better results because I plan my routes in advance."),
                Testimonial(avatar: "📈", name: "Dana • Field Rep", quote: "Map filters make it obvious which streets are worth revisiting.")
            ]
        }
    }

    private static func faq(for goal: OnboardingProfile.SalesGoal) -> [FAQ] {
        var items: [FAQ]

        switch goal {
        case .organizePipeline:
            items = [FAQ(
                question: "Do I keep the leads I already entered?",
                answer: "Absolutely. Your existing leads stay put—we simply unlock unlimited storage, saved filters, and bulk actions on top of what you have."
            )]
        case .bookMoreAppointments:
            items = [FAQ(
                question: "Can I manage appointments inside the app?",
                answer: "Yes. Schedule visits, set reminders, sync to your device calendar, and mark outcomes without leaving D2D Advancer."
            )]
        case .territoryPlanning:
            items = [FAQ(
                question: "Does D2D Advancer show which streets to start with?",
                answer: "Premium unlocks map layers, demographic overlays, and saved hot lists so you always know the next best blocks."
            )]
        }

        items.append(contentsOf: [
            FAQ(question: "Can I cancel anytime?", answer: "Yes. Cancel anytime from your device settings with no hassle. If you cancel during your 3-day trial, you won't be charged at all."),
            FAQ(question: "What happens to my data if I cancel?", answer: "Your leads, notes, and appointments stay on your device. You can always resubscribe later and pick up right where you left off—nothing gets deleted."),
            FAQ(question: "Is my data secure and private?", answer: "Absolutely. We use industry-standard encryption, automatic cloud backups, and never sell or share your customer information with third parties.")
        ])

        return items
    }

    private static func recommendedPlan(
        for focuses: Set<OnboardingProfile.FocusArea>,
        salesGoal: OnboardingProfile.SalesGoal,
        workflow: OnboardingProfile.WorkflowStyle
    ) -> PaywallManager.SubscriptionPlan {
        if salesGoal == .bookMoreAppointments || focuses.contains(.territoryInsights) {
            return .yearly
        }

        if workflow == .hustle && focuses.count <= 2 {
            return .weekly
        }

        if focuses.contains(.automatedReminders) {
            return .yearly
        }

        return .yearly
    }
}

class PaywallManager: ObservableObject {
    enum SubscriptionPlan: Hashable {
        case weekly
        case yearly
    }

    static let shared = PaywallManager()

    @Published var isPremium: Bool = false
    @Published var leadCount: Int = 0
    @Published var shouldShowPaywall: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var isLoadingProducts: Bool = false
    @Published var products: [Product] = []
    @Published var purchaseStatusMessage: String?
    @Published var purchaseStatusIsError: Bool = false
    @Published private(set) var hasAttemptedProductLoad: Bool = false
    @Published private(set) var experience: PaywallExperience

    private let userDefaults = UserDefaults.standard
    private let premiumKey = "isPremiumUser"
    private let leadCountKey = "totalLeadCount"
    private let freeLeadLimit = 0 // Subscription required (3-day trial available)
    private var isPremiumUnlockedForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-unlockPremiumForUITests")
    }
    private var isStoreKitDisabledForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableStoreKitForUITests")
    }

    // Product IDs - UPDATE THESE to match your App Store Connect IDs
    private let weeklyProductID = "com.d2dadvancer.weekly"
    private let yearlyProductID = "com.d2dadvancer.yearly"

    private var updateListenerTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        experience = PaywallExperience(profile: OnboardingManager.shared.profile)
        loadPremiumStatus()
        loadLeadCount()

        if !isStoreKitDisabledForUITests {
            updateListenerTask = listenForTransactions()

            Task {
                await loadProducts()
                await checkSubscriptionStatus()
            }
        } else {
            print("🧪 StoreKit disabled for UI tests")
        }

        OnboardingManager.shared.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.experience = PaywallExperience(profile: profile)
            }
            .store(in: &cancellables)

        // Listen for app becoming active to recheck subscription status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        print("📱 App became active - rechecking subscription status")
        Task {
            await checkSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Action Gating

    func incrementLeadCount() {
        leadCount += 1
        userDefaults.set(leadCount, forKey: leadCountKey)
        userDefaults.synchronize()

        if !isPremium && !isPremiumUnlockedForUITests && leadCount >= freeLeadLimit {
            let onboardingCompleted = userDefaults.bool(forKey: "onboarding_completed")
            if onboardingCompleted && !shouldShowPaywall {
                shouldShowPaywall = true
            }
        }
    }

    func canAddLead() -> Bool {
        if isPremium || isPremiumUnlockedForUITests {
            return true
        }
        return leadCount < freeLeadLimit
    }

    func remainingFreeLeads() -> Int {
        if isPremium || isPremiumUnlockedForUITests {
            return Int.max
        }
        return max(0, freeLeadLimit - leadCount)
    }

    /// Gate an action behind the paywall. Returns true if the user is premium and the action can proceed.
    /// Shows the paywall if the user is not premium.
    @discardableResult
    func gateAction() -> Bool {
        if isPremium || isPremiumUnlockedForUITests { return true }
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        shouldShowPaywall = true
        return false
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        let productID = productID(for: plan)
        return products.first { $0.id == productID }
    }

    func displayPrice(for plan: SubscriptionPlan) -> String {
        guard let product = product(for: plan) else {
            return isLoadingProducts || !hasAttemptedProductLoad ? "Loading" : "Unavailable"
        }

        return product.displayPrice
    }

    func purchaseCaption(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly:
            guard let price = product(for: .weekly)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading weekly price" : "Weekly plan unavailable"
            }

            return "3 days free, then \(price)/week"
        case .yearly:
            guard let price = product(for: .yearly)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading yearly price" : "Yearly plan unavailable"
            }

            return "\(price)/year - best value"
        }
    }

    private func productID(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: return weeklyProductID
        case .yearly: return yearlyProductID
        }
    }

    private func setPurchaseStatus(_ message: String?, isError: Bool = false) {
        purchaseStatusMessage = message
        purchaseStatusIsError = isError
    }

    // MARK: - Premium Status

    private func loadPremiumStatus() {
        if isPremiumUnlockedForUITests {
            isPremium = true
            shouldShowPaywall = false
            userDefaults.set(true, forKey: premiumKey)
            print("💎 Premium status: Active (UI test unlock)")
            return
        }

        isPremium = userDefaults.bool(forKey: premiumKey)
        print("💎 Premium status: \(isPremium ? "Active" : "Inactive")")
    }

    private func loadLeadCount() {
        leadCount = userDefaults.integer(forKey: leadCountKey)
        print("📊 Loaded lead count: \(leadCount)")
    }

    func setPremiumStatus(_ premium: Bool) {
        let wasPreviouslyPremium = isPremium
        isPremium = premium
        userDefaults.set(premium, forKey: premiumKey)
        userDefaults.synchronize()

        if premium {
            // User is premium - hide paywall
            shouldShowPaywall = false
            print("💎 Premium status updated: Active")
        } else {
            // User is not premium
            print("💎 Premium status updated: Inactive")

            // If subscription expired, don't auto-show paywall — it will show on next action via gateAction()
            if wasPreviouslyPremium && !premium {
                print("⚠️ Subscription expired or cancelled — paywall will show on next action")
            }
        }

        NotificationCenter.default.post(
            name: .paywallPremiumStatusChanged,
            object: nil,
            userInfo: ["isPremium": premium]
        )
    }

    // MARK: - StoreKit 2 Product Loading

    @MainActor
    func loadProducts() async {
        guard !isStoreKitDisabledForUITests else {
            hasAttemptedProductLoad = true
            products = []
            return
        }

        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        purchaseStatusMessage = nil
        purchaseStatusIsError = false

        defer {
            isLoadingProducts = false
            hasAttemptedProductLoad = true
        }

        do {
            let loadedProducts = try await Product.products(for: [weeklyProductID, yearlyProductID])
            products = loadedProducts.sorted { lhs, rhs in
                productSortOrder(lhs.id) < productSortOrder(rhs.id)
            }

            let loadedProductIDs = Set(loadedProducts.map(\.id))
            let missingProductIDs = Set([weeklyProductID, yearlyProductID]).subtracting(loadedProductIDs)

            if missingProductIDs.isEmpty {
                print("✅ Loaded \(products.count) products")
            } else {
                print("⚠️ Missing StoreKit products: \(missingProductIDs.sorted().joined(separator: ", "))")
                setPurchaseStatus("Subscription options are still loading. Please try again in a moment.", isError: true)
            }
        } catch {
            print("❌ Failed to load products: \(error)")
            products = []
            setPurchaseStatus("We couldn't load subscription options. Check your connection and try again.", isError: true)
        }
    }

    private func productSortOrder(_ productID: String) -> Int {
        switch productID {
        case yearlyProductID: return 0
        case weeklyProductID: return 1
        default: return 2
        }
    }

    // MARK: - Purchase Flow

    @MainActor
    func purchase(plan: SubscriptionPlan) async {
        guard !isPurchasing else { return }

        isPurchasing = true
        setPurchaseStatus(nil)

        defer {
            isPurchasing = false
        }

        if product(for: plan) == nil {
            print("⚠️ Products not loaded yet")
            await loadProducts()
        }

        let productID = productID(for: plan)
        guard let product = product(for: plan) else {
            print("❌ Product not found: \(productID)")
            setPurchaseStatus("This subscription option is unavailable right now. Please try again in a moment.", isError: true)
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()

                await checkSubscriptionStatus()
                setPurchaseStatus("Purchase complete. Pro access is active.")
                print("✅ Purchase successful: \(product.displayName)")

            case .userCancelled:
                setPurchaseStatus(nil)
                print("ℹ️ User cancelled purchase")

            case .pending:
                setPurchaseStatus("Purchase is pending approval. Pro unlocks automatically once Apple approves it.")
                print("⏳ Purchase pending approval")

            @unknown default:
                setPurchaseStatus("We couldn't complete the purchase. Please try again.", isError: true)
                print("❌ Unknown purchase result")
            }
        } catch {
            setPurchaseStatus("Purchase failed: \(error.localizedDescription)", isError: true)
            print("❌ Purchase failed: \(error)")
        }
    }

    @MainActor
    func restorePurchases() async {
        guard !isPurchasing else { return }

        isPurchasing = true
        setPurchaseStatus(nil)

        defer {
            isPurchasing = false
        }

        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()

            if isPremium {
                setPurchaseStatus("Purchases restored. Pro access is active.")
                print("✅ Purchases restored")
            } else {
                setPurchaseStatus("No active subscription was found for this Apple ID.", isError: true)
                print("ℹ️ Restore completed with no active subscription")
            }
        } catch {
            setPurchaseStatus("Restore failed: \(error.localizedDescription)", isError: true)
            print("❌ Restore failed: \(error)")
        }
    }

    // MARK: - Subscription Status

    @MainActor
    func checkSubscriptionStatus() async {
        guard !isPremiumUnlockedForUITests else {
            setPremiumStatus(true)
            print("🧪 Subscription status check skipped: premium unlocked for UI tests")
            return
        }

        guard !isStoreKitDisabledForUITests else {
            setPremiumStatus(false)
            print("🧪 Subscription status check skipped for UI tests")
            return
        }

        print("🔍 Checking subscription status...")
        var isActive = false
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.productID == weeklyProductID || transaction.productID == yearlyProductID {
                    // Check if subscription is actually active (not expired)
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            isActive = true
                            hasActiveSubscription = true
                            print("✅ Found active subscription: \(transaction.productID)")
                            print("   Expires: \(expirationDate)")
                        } else {
                            print("⚠️ Found expired subscription: \(transaction.productID)")
                            print("   Expired: \(expirationDate)")
                        }
                    } else {
                        // No expiration date means it's active (shouldn't happen for subscriptions but handle it)
                        isActive = true
                        hasActiveSubscription = true
                        print("✅ Found active subscription: \(transaction.productID) (no expiration)")
                    }
                    break
                }
            } catch {
                print("❌ Transaction verification failed: \(error)")
            }
        }

        if !hasActiveSubscription {
            print("❌ No active subscription found")
        }

        setPremiumStatus(isActive)
    }

    /// Force refresh subscription status - useful for manual checks
    func forceRefreshSubscriptionStatus() async {
        print("🔄 Force refreshing subscription status...")
        await checkSubscriptionStatus()
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.checkSubscriptionStatus()
                } catch {
                    print("❌ Transaction update failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }

    // MARK: - Testing & Debug

    func resetPremiumStatus() {
        setPremiumStatus(false)
        print("🔄 Premium status reset")
    }

    func resetAll() {
        resetPremiumStatus()
        shouldShowPaywall = false
        print("🔄 All paywall data reset")
    }
}

extension Notification.Name {
    static let paywallPremiumStatusChanged = Notification.Name("PaywallPremiumStatusChanged")
}
