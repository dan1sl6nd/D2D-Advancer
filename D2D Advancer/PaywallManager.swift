import Foundation
import SwiftUI
import StoreKit
import CryptoKit
import FirebaseAuth

enum SubscriptionProductCatalog {
    static let legacyWeekly = "com.d2dadvancer.weekly"
    static let legacyYearly = "com.d2dadvancer.yearly"
    static let legacyMonthly = "com.d2dadvancer.monthly"
    static let legacyTeamMonthly = "com.d2dadvancer.team.monthly"
    static let legacyTeamYearly = "com.d2dadvancer.team.yearly"
    static let soloMonthly = "com.d2dadvancer.solo.monthly"
    static let soloYearly = "com.d2dadvancer.solo.yearly"
    static let teamMonthly = "com.d2dadvancer.team3.monthly"
    static let teamYearly = "com.d2dadvancer.team3.yearly"

    static let all = [
        legacyWeekly,
        legacyYearly,
        soloMonthly,
        soloYearly,
        teamMonthly,
        teamYearly
    ]

    static let recognized = Set(all + [
        legacyMonthly,
        legacyTeamMonthly,
        legacyTeamYearly
    ])

    static let team = Set([
        legacyTeamMonthly,
        legacyTeamYearly,
        teamMonthly,
        teamYearly
    ])

    static func recognizes(_ productID: String) -> Bool {
        recognized.contains(productID)
    }
}

class PaywallManager: ObservableObject {
    enum Offering: Equatable {
        case solo
        case team
    }

    enum SubscriptionPlan: Hashable {
        case weekly
        case monthly
        case yearly
        case teamMonthly
        case teamYearly

        var isTeamPlan: Bool {
            self == .teamMonthly || self == .teamYearly
        }

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
    @Published private(set) var offering: Offering = .solo
    @Published private(set) var hasActiveTeamStoreSubscription = false

    private let userDefaults = UserDefaults.standard
    private let premiumKey = "isPremiumUser"
    private let leadCountKey = "totalLeadCount"
    private let freeLeadLimit = 0 // Subscription required.
    private var hasStoreEntitlement = false
    private var hasTeamWorkspaceEntitlement = false
    private var isPremiumUnlockedForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-unlockPremiumForUITests")
    }
    private var isStoreKitDisabledForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableStoreKitForUITests")
    }

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        loadPremiumStatus()
        loadLeadCount()

        if !isStoreKitDisabledForUITests {
            updateListenerTask = listenForTransactions()
        } else {
            print("🧪 StoreKit disabled for UI tests")
        }

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
        offering = .solo
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        shouldShowPaywall = true
        return false
    }

    func showTeamPaywall() {
        offering = .team
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        shouldShowPaywall = true
    }

    func showSoloPaywall() {
        offering = .solo
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        shouldShowPaywall = true
    }

    var defaultPlan: SubscriptionPlan {
        offering == .team ? .teamYearly : .yearly
    }

    var visiblePlans: [SubscriptionPlan] {
        switch offering {
        case .solo:
            var plans: [SubscriptionPlan] = [.yearly]
            if product(for: .monthly) != nil {
                plans.append(.monthly)
            }
            return plans
        case .team:
            return [.teamYearly, .teamMonthly]
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        let productID = productID(for: plan)
        if let product = products.first(where: { $0.id == productID }) {
            return product
        }
        if plan == .yearly {
            return products.first { $0.id == SubscriptionProductCatalog.legacyYearly }
        }
        return nil
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
        case .monthly, .teamMonthly:
            guard let price = product(for: plan)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading monthly price" : "Monthly plan unavailable"
            }
            return "\(price)/month"
        case .yearly:
            guard let price = product(for: .yearly)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading yearly price" : "Yearly plan unavailable"
            }
            return "\(price)/year - best value"
        case .teamYearly:
            guard let price = product(for: .teamYearly)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading yearly price" : "Yearly Team plan unavailable"
            }
            return "\(price)/year - owner + 2 workers"
        }
    }

    private func productID(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: return SubscriptionProductCatalog.legacyWeekly
        case .monthly: return SubscriptionProductCatalog.soloMonthly
        case .yearly: return SubscriptionProductCatalog.soloYearly
        case .teamMonthly: return SubscriptionProductCatalog.teamMonthly
        case .teamYearly: return SubscriptionProductCatalog.teamYearly
        }
    }

    func planTitle(_ plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: return "Weekly"
        case .monthly, .teamMonthly: return "Monthly"
        case .yearly, .teamYearly: return "Yearly"
        }
    }

    func planPeriod(_ plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: return "/ week"
        case .monthly, .teamMonthly: return "/ month"
        case .yearly, .teamYearly: return "/ year"
        }
    }

    private var allProductIDs: [String] {
        SubscriptionProductCatalog.all
    }

    private func isRecognizedProductID(_ productID: String) -> Bool {
        SubscriptionProductCatalog.recognizes(productID)
    }

    private func isTeamProductID(_ productID: String) -> Bool {
        SubscriptionProductCatalog.team.contains(productID)
    }

    private func setPurchaseStatus(_ message: String?, isError: Bool = false) {
        purchaseStatusMessage = message
        purchaseStatusIsError = isError
    }

    // MARK: - Premium Status

    private func loadPremiumStatus() {
        if isPremiumUnlockedForUITests {
            hasStoreEntitlement = true
            isPremium = true
            shouldShowPaywall = false
            userDefaults.set(true, forKey: premiumKey)
            print("💎 Premium status: Active (UI test unlock)")
            return
        }

        hasStoreEntitlement = userDefaults.bool(forKey: premiumKey)
        isPremium = hasStoreEntitlement
        print("💎 Premium status: \(isPremium ? "Active" : "Inactive")")
    }

    private func loadLeadCount() {
        leadCount = userDefaults.integer(forKey: leadCountKey)
        print("📊 Loaded lead count: \(leadCount)")
    }

    func setPremiumStatus(_ premium: Bool) {
        hasStoreEntitlement = premium
        userDefaults.set(premium, forKey: premiumKey)
        userDefaults.synchronize()
        refreshEffectivePremiumStatus()
    }

    func setTeamWorkspaceAccess(_ active: Bool) {
        hasTeamWorkspaceEntitlement = active
        refreshEffectivePremiumStatus()
    }

    private func refreshEffectivePremiumStatus() {
        let wasPreviouslyPremium = isPremium
        let premium = hasStoreEntitlement || hasTeamWorkspaceEntitlement || isPremiumUnlockedForUITests
        if isPremium != premium {
            isPremium = premium
        }

        if premium {
            if shouldShowPaywall {
                shouldShowPaywall = false
            }
            print("💎 Premium status updated: Active")
        } else {
            print("💎 Premium status updated: Inactive")
            if wasPreviouslyPremium && !premium {
                print("⚠️ Subscription expired or cancelled — paywall will show on next action")
            }
        }

        if premium != wasPreviouslyPremium {
            NotificationCenter.default.post(
                name: .paywallPremiumStatusChanged,
                object: nil,
                userInfo: ["isPremium": premium]
            )
        }
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
            let loadedProducts = try await Product.products(for: allProductIDs)
            products = loadedProducts.sorted { lhs, rhs in
                productSortOrder(lhs.id) < productSortOrder(rhs.id)
            }

            let loadedProductIDs = Set(loadedProducts.map(\.id))
            let missingProductIDs = Set(allProductIDs).subtracting(loadedProductIDs)

            print("✅ Loaded \(products.count) StoreKit products")
            if !missingProductIDs.isEmpty {
                print("⚠️ Missing StoreKit products: \(missingProductIDs.sorted().joined(separator: ", "))")
            }
            if loadedProducts.isEmpty {
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
        case SubscriptionProductCatalog.soloYearly: return 0
        case SubscriptionProductCatalog.soloMonthly: return 1
        case SubscriptionProductCatalog.teamYearly: return 2
        case SubscriptionProductCatalog.teamMonthly: return 3
        case SubscriptionProductCatalog.legacyYearly: return 4
        case SubscriptionProductCatalog.legacyWeekly: return 5
        default: return 6
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
            let purchaseOptions = try purchaseOptions(for: plan)
            let result = try await product.purchase(options: purchaseOptions)

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                if plan.isTeamPlan {
                    try await TeamBillingService.shared.syncTeamEntitlement(
                        signedTransaction: verification.jwsRepresentation
                    )
                }
                await transaction.finish()

                await checkSubscriptionStatus()
                setPurchaseStatus(
                    plan.isTeamPlan
                        ? "Team plan active. You can create the workspace now."
                        : "Purchase complete. Pro access is active."
                )
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

    private func purchaseOptions(for plan: SubscriptionPlan) throws -> Set<Product.PurchaseOption> {
        guard plan.isTeamPlan else { return [] }
        guard let userId = Auth.auth().currentUser?.uid else {
            throw TeamFirebaseServiceError.notAuthenticated
        }
        return [.appAccountToken(Self.teamAppAccountToken(for: userId))]
    }

    static func teamAppAccountToken(for userId: String) -> UUID {
        let digest = SHA256.hash(data: Data("d2d-team:\(userId)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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

            if hasStoreEntitlement {
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
        var hasActiveSubscription = false
        var hasActiveTeamSubscription = false
        var teamSignedTransaction: String?

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                guard isRecognizedProductID(transaction.productID) else { continue }
                let isCurrent = transaction.revocationDate == nil
                    && (transaction.expirationDate.map { $0 > Date() } ?? true)
                guard isCurrent else {
                    print("⚠️ Found inactive subscription: \(transaction.productID)")
                    continue
                }

                hasActiveSubscription = true
                if isTeamProductID(transaction.productID) {
                    hasActiveTeamSubscription = true
                    teamSignedTransaction = result.jwsRepresentation
                }
                print("✅ Found active subscription: \(transaction.productID)")
            } catch {
                print("❌ Transaction verification failed: \(error)")
            }
        }

        if !hasActiveSubscription {
            print("❌ No active subscription found")
        }

        hasActiveTeamStoreSubscription = hasActiveTeamSubscription
        setPremiumStatus(hasActiveSubscription)

        if let teamSignedTransaction, Auth.auth().currentUser != nil {
            do {
                try await TeamBillingService.shared.syncTeamEntitlement(
                    signedTransaction: teamSignedTransaction
                )
            } catch {
                print("⚠️ Team entitlement sync deferred: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func activeTeamTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard isTeamProductID(transaction.productID),
                      transaction.revocationDate == nil,
                      transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                    continue
                }
                return result.jwsRepresentation
            } catch {
                print("⚠️ Ignoring unverified Team transaction: \(error.localizedDescription)")
            }
        }
        return nil
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
                    if self.isTeamProductID(transaction.productID) {
                        try await TeamBillingService.shared.syncTeamEntitlement(
                            signedTransaction: result.jwsRepresentation
                        )
                    }
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
        hasTeamWorkspaceEntitlement = false
        hasActiveTeamStoreSubscription = false
        resetPremiumStatus()
        shouldShowPaywall = false
        print("🔄 All paywall data reset")
    }
}

extension Notification.Name {
    static let paywallPremiumStatusChanged = Notification.Name("PaywallPremiumStatusChanged")
}
