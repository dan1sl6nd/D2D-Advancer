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

enum TeamStoreTransactionServerEligibility: Equatable {
    case eligible
    case missingAccountToken
    case xcode

    fileprivate var selectionPriority: Int {
        switch self {
        case .eligible:
            return 2
        case .missingAccountToken:
            return 1
        case .xcode:
            return 0
        }
    }

    var canAttemptServerVerification: Bool {
        self != .xcode
    }

    func countsAsStoreEntitlement(allowsLocalStoreKit: Bool) -> Bool {
        self != .xcode || allowsLocalStoreKit
    }

    static func evaluate(environment: AppStore.Environment, hasAppAccountToken: Bool) -> Self {
        if environment == .xcode {
            return .xcode
        }
        return hasAppAccountToken ? .eligible : .missingAccountToken
    }
}

struct TeamStoreTransactionCandidate {
    let jwsRepresentation: String
    let eligibility: TeamStoreTransactionServerEligibility
    let expirationDate: Date
    let originalTransactionID: UInt64

    func isPreferred(over current: Self?) -> Bool {
        guard let current else {
            return true
        }
        if eligibility.selectionPriority != current.eligibility.selectionPriority {
            return eligibility.selectionPriority > current.eligibility.selectionPriority
        }
        return expirationDate > current.expirationDate
    }
}

struct PurchaseRestoreResult: Identifiable {
    enum Kind: Equatable {
        case restored
        case noPurchaseFound
        case testPurchase
        case accountLinkRequired
        case timedOut
        case failed
    }

    let id = UUID()
    let kind: Kind
    let message: String

    var title: String {
        switch kind {
        case .restored:
            return "Purchases Restored"
        case .noPurchaseFound:
            return "No Purchase Found"
        case .testPurchase:
            return "Test Purchase Not Restored"
        case .accountLinkRequired:
            return "Team Purchase Needs Attention"
        case .timedOut:
            return "Restore Taking Too Long"
        case .failed:
            return "Restore Failed"
        }
    }

    var isSuccess: Bool {
        kind == .restored
    }
}

private actor AppStoreSyncAttempt {
    enum Outcome {
        case completed
        case failed(String)
    }

    private var hasStarted = false
    private var outcome: Outcome?
    private let operation: @Sendable () async throws -> Void

    init(operation: @escaping @Sendable () async throws -> Void = {
        try await AppStore.sync()
    }) {
        self.operation = operation
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try await operation()
            outcome = .completed
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    func currentOutcome() -> Outcome? {
        outcome
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
    @Published private(set) var hasVerifiedTeamBillingEntitlement = false
    @Published private(set) var activeTeamServerEligibility: TeamStoreTransactionServerEligibility?
    @Published private(set) var hasIgnoredLocalTeamTransaction = false
    @Published private(set) var eligibleTrialDurations: [String: String] = [:]

    private let userDefaults = UserDefaults.standard
    private let premiumKey = "isPremiumUser"
    private let leadCountKey = "totalLeadCount"
    private let freeLeadLimit = 0 // Subscription required.
    private var hasStoreEntitlement = false
    private var hasTeamWorkspaceEntitlement = false
    private var verifiedTeamBillingOwnerUserID: String?
    private var verifiedTeamOriginalTransactionID: UInt64?
    private var isPremiumUnlockedForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-unlockPremiumForUITests")
    }
    private var isStoreKitDisabledForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableStoreKitForUITests")
    }
    private var allowsLocalStoreKitTransactions: Bool {
        ProcessInfo.processInfo.arguments.contains("-allowLocalStoreKitTransactions")
    }
    private var simulatesStoreKitRestoreTimeoutForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-simulateStoreKitRestoreTimeoutForUITests")
    }

    private var updateListenerTask: Task<Void, Error>?
    private var activeAppStoreSyncAttempt: AppStoreSyncAttempt?

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

    func showTeamPaywall(message: String? = nil, isError: Bool = false) {
        offering = .team
        purchaseStatusMessage = message
        purchaseStatusIsError = isError
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
            if let duration = eligibleTrialDuration(for: plan) {
                return "\(duration.capitalized) free, then \(price)/year"
            }
            return "\(price)/year - best value"
        case .teamYearly:
            guard let price = product(for: .teamYearly)?.displayPrice else {
                return isLoadingProducts || !hasAttemptedProductLoad ? "Loading yearly price" : "Yearly Team plan unavailable"
            }
            if let duration = eligibleTrialDuration(for: plan) {
                return "\(duration.capitalized) free, then \(price)/year"
            }
            return "\(price)/year - owner + 2 workers"
        }
    }

    func eligibleTrialDuration(for plan: SubscriptionPlan) -> String? {
        guard let product = product(for: plan) else { return nil }
        return eligibleTrialDurations[product.id]
    }

    func trialButtonTitle(for plan: SubscriptionPlan) -> String? {
        guard let duration = eligibleTrialDuration(for: plan) else { return nil }
        if duration == "14 days" {
            return "Start 14-Day Free Trial"
        }
        return "Start Free Trial"
    }

    func renewalDisclosure(for plan: SubscriptionPlan) -> String {
        guard let product = product(for: plan) else {
            return "Apple shows the final price and renewal terms before purchase."
        }
        let period = plan == .monthly || plan == .teamMonthly ? "month" : "year"
        if let duration = eligibleTrialDuration(for: plan) {
            return "No charge for \(duration). Then \(product.displayPrice)/\(period), renewing automatically unless cancelled."
        }
        return "\(product.displayPrice)/\(period), renewing automatically unless cancelled."
    }

    static func trialDurationText(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let normalizedValue = max(value, 1)
        switch unit {
        case .day:
            return "\(normalizedValue) day\(normalizedValue == 1 ? "" : "s")"
        case .week:
            if normalizedValue == 2 { return "14 days" }
            return "\(normalizedValue) week\(normalizedValue == 1 ? "" : "s")"
        case .month:
            return "\(normalizedValue) month\(normalizedValue == 1 ? "" : "s")"
        case .year:
            return "\(normalizedValue) year\(normalizedValue == 1 ? "" : "s")"
        @unknown default:
            return "a limited time"
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
            eligibleTrialDurations = await eligibleFreeTrialDurations(in: loadedProducts)

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
            eligibleTrialDurations = [:]
            setPurchaseStatus("We couldn't load subscription options. Check your connection and try again.", isError: true)
        }
    }

    private func eligibleFreeTrialDurations(in products: [Product]) async -> [String: String] {
        var durations: [String: String] = [:]
        for product in products {
            guard let subscription = product.subscription,
                  let offer = subscription.introductoryOffer,
                  offer.paymentMode == .freeTrial,
                  await subscription.isEligibleForIntroOffer else {
                continue
            }
            durations[product.id] = Self.trialDurationText(
                value: offer.period.value,
                unit: offer.period.unit
            )
        }
        return durations
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
                    let eligibility = TeamStoreTransactionServerEligibility.evaluate(
                        environment: transaction.environment,
                        hasAppAccountToken: transaction.appAccountToken != nil
                    )
                    guard eligibility.countsAsStoreEntitlement(
                        allowsLocalStoreKit: allowsLocalStoreKitTransactions
                    ) else {
                        await transaction.finish()
                        await checkSubscriptionStatus(syncTeamBilling: false)
                        setPurchaseStatus(
                            "A local Xcode test purchase cannot activate a real Team. Use this screen without the Local StoreKit scheme to buy through Apple.",
                            isError: true
                        )
                        return
                    }
                    let linkingError: Error?
                    do {
                        let entitlement = try await TeamBillingService.shared.syncTeamEntitlement(
                            signedTransaction: verification.jwsRepresentation
                        )
                        guard entitlement.planStatus == .active else {
                            throw TeamBillingServiceError.invalidServerResponse
                        }
                        markTeamBillingVerified(for: transaction)
                        linkingError = nil
                    } catch {
                        clearVerifiedTeamBilling()
                        linkingError = error
                    }
                    await transaction.finish()
                    await checkSubscriptionStatus(syncTeamBilling: false)

                    if let linkingError {
                        setPurchaseStatus(
                            "Apple completed the Team purchase, but this owner account is not linked yet. Sign in with the purchasing D2D account and tap Restore Purchases. \(linkingError.localizedDescription)",
                            isError: true
                        )
                    } else {
                        setPurchaseStatus("Team plan verified. You can create the workspace now.")
                    }
                    print("✅ Team purchase completed by Apple: \(product.displayName)")
                    return
                }
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
    func restorePurchases() async -> PurchaseRestoreResult? {
        guard !isPurchasing else { return nil }

        isPurchasing = true
        setPurchaseStatus("Checking the App Store for previous purchases...")

        defer {
            isPurchasing = false
        }

#if DEBUG
        if isStoreKitDisabledForUITests, !simulatesStoreKitRestoreTimeoutForUITests {
            return completeRestore(
                kind: .noPurchaseFound,
                message: "No active D2D Advancer subscription was found for this Apple ID."
            )
        }
#endif

        switch await synchronizeAppStore() {
        case .completed:
            await checkSubscriptionStatus()

            if offering == .team, hasIgnoredLocalTeamTransaction, !hasActiveTeamStoreSubscription {
                return completeRestore(
                    kind: .testPurchase,
                    message: "A local Xcode test purchase was ignored. Choose a Team plan below to subscribe through the App Store."
                )
            } else if offering == .team, hasActiveTeamStoreSubscription, !hasVerifiedTeamBillingEntitlement {
                switch activeTeamServerEligibility {
                case .xcode:
                    return completeRestore(
                        kind: .testPurchase,
                        message: "This is an Xcode test subscription. Use an App Store Sandbox or live Team subscription for a real workspace."
                    )
                case .missingAccountToken:
                    return completeRestore(
                        kind: .accountLinkRequired,
                        message: "Apple found an older Team subscription, but it is not linked to this signed-in owner. Contact support before purchasing again."
                    )
                case .eligible, .none:
                    return completeRestore(
                        kind: .accountLinkRequired,
                        message: "Apple found a Team subscription, but it is not linked to this signed-in owner. Sign in with the D2D account that purchased it, then try again."
                    )
                }
            } else if offering == .team, hasVerifiedTeamBillingEntitlement {
                print("✅ Team purchase restored")
                return completeRestore(
                    kind: .restored,
                    message: "Team purchase restored and verified for this owner."
                )
            } else if hasStoreEntitlement {
                print("✅ Purchases restored")
                return completeRestore(
                    kind: .restored,
                    message: "Purchases restored. Pro access is active."
                )
            } else {
                print("ℹ️ Restore completed with no active subscription")
                return completeRestore(
                    kind: .noPurchaseFound,
                    message: "No active D2D Advancer subscription was found for this Apple ID."
                )
            }
        case .failed(let message):
            print("❌ Restore failed: \(message)")
            return completeRestore(
                kind: .failed,
                message: "Restore failed: \(message)"
            )
        case .timedOut:
            print("⚠️ Restore timed out while waiting for App Store.sync()")
            return completeRestore(
                kind: .timedOut,
                message: "The App Store did not finish the restore request. Check your connection, close and reopen D2D Advancer, then tap Restore Purchases again. Restoring never charges you."
            )
        }
    }

    private enum AppStoreSyncResult {
        case completed
        case failed(String)
        case timedOut
    }

    @MainActor
    private func synchronizeAppStore() async -> AppStoreSyncResult {
        let attempt: AppStoreSyncAttempt
        if let activeAppStoreSyncAttempt {
            attempt = activeAppStoreSyncAttempt
        } else {
            let newAttempt: AppStoreSyncAttempt
#if DEBUG
            if simulatesStoreKitRestoreTimeoutForUITests {
                newAttempt = AppStoreSyncAttempt {
                    try await Task.sleep(for: .seconds(30))
                }
            } else {
                newAttempt = AppStoreSyncAttempt()
            }
#else
            newAttempt = AppStoreSyncAttempt()
#endif
            activeAppStoreSyncAttempt = newAttempt
            attempt = newAttempt
            Task {
                await newAttempt.start()
            }
        }

        let clock = ContinuousClock()
        let timeout: Duration = simulatesStoreKitRestoreTimeoutForUITests
            ? .seconds(1)
            : .seconds(60)
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if let outcome = await attempt.currentOutcome() {
                activeAppStoreSyncAttempt = nil
                switch outcome {
                case .completed:
                    return .completed
                case .failed(let message):
                    return .failed(message)
                }
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return .failed("The restore request was cancelled.")
            }
        }

        if let outcome = await attempt.currentOutcome() {
            activeAppStoreSyncAttempt = nil
            switch outcome {
            case .completed:
                return .completed
            case .failed(let message):
                return .failed(message)
            }
        }

        return .timedOut
    }

    @MainActor
    private func completeRestore(
        kind: PurchaseRestoreResult.Kind,
        message: String
    ) -> PurchaseRestoreResult {
        let result = PurchaseRestoreResult(kind: kind, message: message)
        setPurchaseStatus(message, isError: !result.isSuccess)
        return result
    }

    // MARK: - Subscription Status

    @MainActor
    func checkSubscriptionStatus(syncTeamBilling: Bool = true) async {
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
        var ignoredLocalTeamTransaction = false
        var selectedTeamTransaction: TeamStoreTransactionCandidate?

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

                let teamEligibility = isTeamProductID(transaction.productID)
                    ? TeamStoreTransactionServerEligibility.evaluate(
                        environment: transaction.environment,
                        hasAppAccountToken: transaction.appAccountToken != nil
                    )
                    : nil
                if transaction.environment == .xcode && !allowsLocalStoreKitTransactions {
                    if teamEligibility != nil {
                        ignoredLocalTeamTransaction = true
                    }
                    print("⚠️ Ignoring local Xcode subscription outside the Local StoreKit scheme: \(transaction.productID)")
                    continue
                }

                hasActiveSubscription = true
                if let teamEligibility {
                    hasActiveTeamSubscription = true
                    let candidate = TeamStoreTransactionCandidate(
                        jwsRepresentation: result.jwsRepresentation,
                        eligibility: teamEligibility,
                        expirationDate: transaction.expirationDate ?? .distantFuture,
                        originalTransactionID: transaction.originalID
                    )
                    if candidate.isPreferred(over: selectedTeamTransaction) {
                        selectedTeamTransaction = candidate
                    }
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
        activeTeamServerEligibility = selectedTeamTransaction?.eligibility
        hasIgnoredLocalTeamTransaction = ignoredLocalTeamTransaction
        setPremiumStatus(hasActiveSubscription)

        guard hasActiveTeamSubscription,
              let selectedTeamTransaction,
              let ownerUserID = Auth.auth().currentUser?.uid else {
            clearVerifiedTeamBilling()
            return
        }

        let alreadyVerified = verifiedTeamBillingOwnerUserID == ownerUserID
            && verifiedTeamOriginalTransactionID == selectedTeamTransaction.originalTransactionID
        if !alreadyVerified {
            clearVerifiedTeamBilling()
        }

        if syncTeamBilling {
            guard selectedTeamTransaction.eligibility.canAttemptServerVerification else {
                clearVerifiedTeamBilling()
                print("⚠️ Team entitlement is not eligible for production server verification: \(selectedTeamTransaction.eligibility)")
                return
            }
            do {
                let entitlement = try await TeamBillingService.shared.syncTeamEntitlement(
                    signedTransaction: selectedTeamTransaction.jwsRepresentation
                )
                guard entitlement.planStatus == .active else {
                    throw TeamBillingServiceError.invalidServerResponse
                }
                verifiedTeamBillingOwnerUserID = ownerUserID
                verifiedTeamOriginalTransactionID = selectedTeamTransaction.originalTransactionID
                hasVerifiedTeamBillingEntitlement = true
            } catch {
                print("⚠️ Team entitlement sync deferred: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func activeTeamTransaction() async -> TeamStoreTransactionCandidate? {
        var selectedCandidate: TeamStoreTransactionCandidate?
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard isTeamProductID(transaction.productID),
                      transaction.revocationDate == nil,
                      transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                    continue
                }
                let candidate = TeamStoreTransactionCandidate(
                    jwsRepresentation: result.jwsRepresentation,
                    eligibility: TeamStoreTransactionServerEligibility.evaluate(
                        environment: transaction.environment,
                        hasAppAccountToken: transaction.appAccountToken != nil
                    ),
                    expirationDate: transaction.expirationDate ?? .distantFuture,
                    originalTransactionID: transaction.originalID
                )
                guard candidate.eligibility.countsAsStoreEntitlement(
                    allowsLocalStoreKit: allowsLocalStoreKitTransactions
                ) else {
                    continue
                }
                if candidate.isPreferred(over: selectedCandidate) {
                    selectedCandidate = candidate
                }
            } catch {
                print("⚠️ Ignoring unverified Team transaction: \(error.localizedDescription)")
            }
        }
        return selectedCandidate
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
                        let eligibility = TeamStoreTransactionServerEligibility.evaluate(
                            environment: transaction.environment,
                            hasAppAccountToken: transaction.appAccountToken != nil
                        )
                        if eligibility == .eligible {
                            do {
                                let entitlement = try await TeamBillingService.shared.syncTeamEntitlement(
                                    signedTransaction: result.jwsRepresentation
                                )
                                if entitlement.planStatus == .active {
                                    await self.markTeamBillingVerified(for: transaction)
                                }
                            } catch {
                                print("⚠️ Team transaction will retry server sync later: \(error.localizedDescription)")
                            }
                        } else {
                            print("⚠️ Team transaction skipped server sync: \(eligibility)")
                        }
                    }
                    await transaction.finish()
                    await self.checkSubscriptionStatus(syncTeamBilling: false)
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

    @MainActor
    private func markTeamBillingVerified(for transaction: StoreKit.Transaction) {
        guard let ownerUserID = Auth.auth().currentUser?.uid else {
            clearVerifiedTeamBilling()
            return
        }
        verifiedTeamBillingOwnerUserID = ownerUserID
        verifiedTeamOriginalTransactionID = transaction.originalID
        hasVerifiedTeamBillingEntitlement = true
    }

    @MainActor
    private func clearVerifiedTeamBilling() {
        verifiedTeamBillingOwnerUserID = nil
        verifiedTeamOriginalTransactionID = nil
        hasVerifiedTeamBillingEntitlement = false
    }

    // MARK: - Testing & Debug

    func resetPremiumStatus() {
        setPremiumStatus(false)
        print("🔄 Premium status reset")
    }

    @MainActor
    func resetAll() {
        hasTeamWorkspaceEntitlement = false
        hasActiveTeamStoreSubscription = false
        activeTeamServerEligibility = nil
        hasIgnoredLocalTeamTransaction = false
        clearVerifiedTeamBilling()
        eligibleTrialDurations = [:]
        resetPremiumStatus()
        shouldShowPaywall = false
        print("🔄 All paywall data reset")
    }
}

extension Notification.Name {
    static let paywallPremiumStatusChanged = Notification.Name("PaywallPremiumStatusChanged")
}
