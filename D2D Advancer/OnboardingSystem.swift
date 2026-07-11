import SwiftUI
import CoreLocation
import UserNotifications

// MARK: - Onboarding Data Model

struct OnboardingProfile: Codable, Equatable {
    enum SalesGoal: String, CaseIterable, Codable, Identifiable {
        case organizePipeline
        case bookMoreAppointments
        case territoryPlanning

        var id: String { rawValue }

        var title: String {
            switch self {
            case .organizePipeline: return "Manage my leads"
            case .bookMoreAppointments: return "Book appointments"
            case .territoryPlanning: return "Plan my territory"
            }
        }

        var subtitle: String {
            switch self {
            case .organizePipeline: return "Track every door I knock with notes and follow-ups"
            case .bookMoreAppointments: return "Schedule and manage my appointments efficiently"
            case .territoryPlanning: return "Find the best streets and plan my routes"
            }
        }

        var icon: String {
            switch self {
            case .organizePipeline: return "person.text.rectangle.fill"
            case .bookMoreAppointments: return "calendar.badge.clock"
            case .territoryPlanning: return "map.circle.fill"
            }
        }

        var accent: Color {
            switch self {
            case .organizePipeline: return .electricViolet
            case .bookMoreAppointments: return .statusNotHome
            case .territoryPlanning: return .statusInterested
            }
        }
    }

    enum FocusArea: String, CaseIterable, Codable, Identifiable {
        case territoryInsights
        case automatedReminders
        case leadOrganization

        var id: String { rawValue }

        var title: String {
            switch self {
            case .territoryInsights: return "Smart territory planning"
            case .automatedReminders: return "Follow-up reminders"
            case .leadOrganization: return "Lead management"
            }
        }

        var subtitle: String {
            switch self {
            case .territoryInsights: return "See the best neighborhoods and plan optimal routes"
            case .automatedReminders: return "Never miss a follow-up with automatic reminders"
            case .leadOrganization: return "Keep all your leads organized and easy to find"
            }
        }

        var icon: String {
            switch self {
            case .territoryInsights: return "map.circle.fill"
            case .automatedReminders: return "bell.badge.fill"
            case .leadOrganization: return "folder.fill.badge.person.crop"
            }
        }

        var accent: Color {
            switch self {
            case .territoryInsights: return .statusInterested
            case .automatedReminders: return .statusNotHome
            case .leadOrganization: return .electricViolet
            }
        }
    }

    enum WorkflowStyle: String, CaseIterable, Codable, Identifiable {
        case structured
        case hustle

        var id: String { rawValue }

        var title: String {
            switch self {
            case .structured: return "I like planning ahead"
            case .hustle: return "I prefer flexibility"
            }
        }

        var subtitle: String {
            switch self {
            case .structured: return "Organized schedules and planned daily routes"
            case .hustle: return "Quick decisions and adapting on the fly"
            }
        }

        var icon: String {
            switch self {
            case .structured: return "list.bullet.clipboard.fill"
            case .hustle: return "bolt.circle.fill"
            }
        }
    }

    var salesGoal: SalesGoal?
    var focusAreas: Set<FocusArea>
    var workflowStyle: WorkflowStyle?
    var completedAt: Date?

    init(
        salesGoal: SalesGoal? = nil,
        focusAreas: Set<FocusArea> = [],
        workflowStyle: WorkflowStyle? = nil,
        completedAt: Date? = nil
    ) {
        self.salesGoal = salesGoal
        self.focusAreas = focusAreas
        self.workflowStyle = workflowStyle
        self.completedAt = completedAt
    }

    var isComplete: Bool {
        salesGoal != nil &&
        !focusAreas.isEmpty &&
        workflowStyle != nil
    }
}

// MARK: - Onboarding Flow

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case salesGoal
    case focusAreas
    case workflowStyle
    case locationPermission
    case notificationPermission
    case summary

    var index: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome to D2D Advancer"
        case .salesGoal: return "What's your main focus?"
        case .focusAreas: return "What features interest you?"
        case .workflowStyle: return "How do you work?"
        case .locationPermission: return "Enable location services"
        case .notificationPermission: return "Enable notifications"
        case .summary: return "You're all set!"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "Let's personalize your experience in just a few steps"
        case .salesGoal: return "Choose what matters most to you right now"
        case .focusAreas: return "Select the features you're most excited about"
        case .workflowStyle: return "Help us understand your selling style"
        case .locationPermission: return "Track your doors and get territory insights automatically"
        case .notificationPermission: return "Stay on top of follow-ups and never miss an appointment"
        case .summary: return "We've customized D2D Advancer to match your workflow"
        }
    }

    var next: OnboardingPage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self),
              index < all.count - 1 else { return nil }
        return all[index + 1]
    }

    var previous: OnboardingPage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self),
              index > 0 else { return nil }
        return all[index - 1]
    }
}

// MARK: - Manager

class OnboardingManager: ObservableObject {
    @Published var showOnboarding = false
    @Published var currentPage: OnboardingPage = .welcome
    @Published var isCompleted = false
    @Published var profile: OnboardingProfile

    static let shared = OnboardingManager()

    private let userDefaults = UserDefaults.standard
    private let onboardingCompletedKey = "onboarding_completed"
    private let profileKey = "onboarding_profile"
    private let premiumKey = "isPremiumUser"
    private var premiumObserver: NSObjectProtocol?

    private init() {
        if let loadedProfile = Self.loadProfile(from: UserDefaults.standard.data(forKey: profileKey)) {
            profile = loadedProfile
        } else {
            profile = OnboardingProfile()
        }

        checkOnboardingStatus()
        observePremiumStatus()
    }

    var progress: Double {
        let currentIndex = Double(currentPage.index)
        let total = Double(OnboardingPage.allCases.count - 1)
        return max(0, min(1, currentIndex / total))
    }

    func canAdvance(from page: OnboardingPage) -> Bool {
        switch page {
        case .welcome, .summary, .locationPermission, .notificationPermission:
            return true
        case .salesGoal:
            return profile.salesGoal != nil
        case .focusAreas:
            return !profile.focusAreas.isEmpty
        case .workflowStyle:
            return profile.workflowStyle != nil
        }
    }

    func startOnboarding() {
        currentPage = .welcome
        showOnboarding = true
        isCompleted = false
    }

    func nextStep() {
        guard canAdvance(from: currentPage) else { return }

        if currentPage == .summary {
            completeOnboarding()
            return
        }

        if let next = currentPage.next {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                currentPage = next
            }
        }
    }

    func previousStep() {
        guard let previous = currentPage.previous else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentPage = previous
        }
    }

    func completeOnboarding() {
        profile.completedAt = Date()
        saveProfile()

        userDefaults.set(true, forKey: onboardingCompletedKey)

        withAnimation {
            showOnboarding = false
            isCompleted = true
        }

        // Apple Guideline 5.6 Compliant: Subscription-required app with trial option
        // This is acceptable because:
        // 1. Weekly plan offers 3-day free trial (prominently displayed)
        // 2. Yearly plan is direct subscription with best value pricing
        // 3. Clear cancellation policy stated for both plans
        // 4. Messaging is transparent and informative
        // 5. Users can choose the plan that works best for them
        if !PaywallManager.shared.isPremium {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PaywallManager.shared.shouldShowPaywall = true
            }
        }

        Task { @MainActor in
            if FirebaseService.shared.isAuthenticated {
                await FirebaseService.shared.syncCurrentAccountProfileToClouds()
            }
        }
    }

    func resetOnboarding(hard: Bool = false) {
        userDefaults.removeObject(forKey: onboardingCompletedKey)

        if hard {
            userDefaults.removeObject(forKey: profileKey)
            profile = OnboardingProfile()
        }

        checkOnboardingStatus()
    }

    func selectSalesGoal(_ goal: OnboardingProfile.SalesGoal) {
        profile.salesGoal = goal
    }

    func toggleFocusArea(_ focus: OnboardingProfile.FocusArea) {
        if profile.focusAreas.contains(focus) {
            profile.focusAreas.remove(focus)
        } else {
            profile.focusAreas.insert(focus)
        }
    }

    func selectWorkflowStyle(_ style: OnboardingProfile.WorkflowStyle) {
        profile.workflowStyle = style
    }

    private func checkOnboardingStatus() {
        let completed = userDefaults.bool(forKey: onboardingCompletedKey)
        let isPremium = userDefaults.bool(forKey: premiumKey)

        if completed || isPremium {
            showOnboarding = false
            isCompleted = true
        } else {
            showOnboarding = true
            isCompleted = false
        }
    }

    private func saveProfile() {
        do {
            let data = try JSONEncoder().encode(profile)
            userDefaults.set(data, forKey: profileKey)
        } catch {
            print("❌ Failed to encode onboarding profile: \(error.localizedDescription)")
        }
    }

    private static func loadProfile(from data: Data?) -> OnboardingProfile? {
        guard let data else { return nil }
        do {
            let profile = try JSONDecoder().decode(OnboardingProfile.self, from: data)
            return profile
        } catch {
            print("❌ Failed to decode onboarding profile: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func observePremiumStatus() {
        premiumObserver = NotificationCenter.default.addObserver(
            forName: .paywallPremiumStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let isPremium = notification.userInfo?["isPremium"] as? Bool
            else { return }

            if isPremium {
                self.completeOnboarding()
            }
        }
    }

    deinit {
        if let premiumObserver {
            NotificationCenter.default.removeObserver(premiumObserver)
        }
    }
}

// MARK: - Permission Managers

class OnboardingLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var permissionCompletion: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestPermission(completion: @escaping (CLAuthorizationStatus) -> Void) {
        // Store the completion handler
        permissionCompletion = completion

        // Request permission - this shows the system dialog
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // Call completion handler when authorization status changes
        if let completion = permissionCompletion {
            completion(authorizationStatus)
            permissionCompletion = nil // Clear the completion handler
        }
    }
}

// MARK: - Onboarding Interface

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var locationManager = OnboardingLocationManager()
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    private let heroCardHeight: CGFloat = 132

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.obsidianBlack
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    headerSection
                        .padding(.top, ObsidianLayout.safeAreaTop(geometry, extra: 12, minimum: 40))

                    ScrollView {
                        VStack(spacing: 18) {
                            content(
                                for: onboardingManager.currentPage,
                                usesCompactWelcomeLayout: geometry.size.height < 900
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    navigationControls
                        .padding(.bottom, ObsidianLayout.safeAreaBottom(geometry, extra: 16, minimum: 32))
                }
            }
        }
        .onChangeCompat(of: onboardingManager.showOnboarding) { shouldShow in
            if !shouldShow {
                isPresented = false
                dismiss()
            }
        }
        .interactiveDismissDisabled()
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            OnboardingProgressIndicator(
                currentIndex: onboardingManager.currentPage.index,
                total: OnboardingPage.allCases.count
            )

            VStack(spacing: 8) {
                Text(onboardingManager.currentPage.title)
                    .font(.displayMedium)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(onboardingManager.currentPage.subtitle)
                    .font(.obsidianBody)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func content(
        for page: OnboardingPage,
        usesCompactWelcomeLayout: Bool
    ) -> some View {
        switch page {
        case .welcome:
            welcomeContent(usesCompactLayout: usesCompactWelcomeLayout)
        case .salesGoal:
            VStack(spacing: 16) {
                ForEach(OnboardingProfile.SalesGoal.allCases) { goal in
                    SelectionCard(
                        icon: goal.icon,
                        title: goal.title,
                        subtitle: goal.subtitle,
                        accent: goal.accent,
                        isSelected: onboardingManager.profile.salesGoal == goal
                    ) {
                        onboardingManager.selectSalesGoal(goal)
                    }
                    .accessibilityIdentifier("onboardingSalesGoal_\(goal.rawValue)")
                }
            }

        case .focusAreas:
            VStack(alignment: .leading, spacing: 16) {
                Text("Select at least one feature you want to use")
                    .font(.obsidianFootnote)
                    .foregroundColor(.textSecondary)

                VStack(spacing: 16) {
                    ForEach(OnboardingProfile.FocusArea.allCases) { focus in
                        SelectionCard(
                            icon: focus.icon,
                            title: focus.title,
                            subtitle: focus.subtitle,
                            accent: focus.accent,
                            isSelected: onboardingManager.profile.focusAreas.contains(focus)
                        ) {
                            onboardingManager.toggleFocusArea(focus)
                        }
                        .accessibilityIdentifier("onboardingFocusArea_\(focus.rawValue)")
                    }
                }
            }

        case .workflowStyle:
            VStack(spacing: 16) {
                ForEach(OnboardingProfile.WorkflowStyle.allCases) { style in
                    SelectionCard(
                        icon: style.icon,
                        title: style.title,
                        subtitle: style.subtitle,
                        accent: .electricViolet,
                        isSelected: onboardingManager.profile.workflowStyle == style
                    ) {
                        onboardingManager.selectWorkflowStyle(style)
                    }
                    .accessibilityIdentifier("onboardingWorkflowStyle_\(style.rawValue)")
                }
            }

        case .locationPermission:
            locationPermissionContent

        case .notificationPermission:
            notificationPermissionContent

        case .summary:
            summaryContent
        }
    }

    private func welcomeContent(usesCompactLayout: Bool) -> some View {
        VStack(spacing: usesCompactLayout ? 12 : 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .frame(height: usesCompactLayout ? 88 : heroCardHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.displayHero)
                            .foregroundColor(.electricViolet)
                    )
            }

            VStack(spacing: usesCompactLayout ? 8 : 12) {
                FeatureHighlightRow(
                    icon: "mappin.circle.fill",
                    title: "Unlock smarter territory planning",
                    subtitle: "Use heatmaps and neighborhood scores to plan high-converting routes.",
                    isCompact: usesCompactLayout
                )

                FeatureHighlightRow(
                    icon: "checkmark.circle.fill",
                    title: "Stay on top of every lead",
                    subtitle: "Capture doors, notes, and tasks so nothing slips through the cracks.",
                    isCompact: usesCompactLayout
                )

                FeatureHighlightRow(
                    icon: "bolt.badge.clock",
                    title: "Automate tedious follow-ups",
                    subtitle: "Schedule reminders and send proven scripts in one tap.",
                    isCompact: usesCompactLayout
                )
            }
        }
    }

    private var locationPermissionContent: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .frame(height: heroCardHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "location.circle.fill")
                            .font(.displayHero)
                            .foregroundColor(.statusInterested)
                    )
            }

            VStack(spacing: 12) {
                FeatureHighlightRow(
                    icon: "map.fill",
                    title: "Auto-log your doors",
                    subtitle: "We'll track where you knock so you can focus on the conversation, not the paperwork."
                )

                FeatureHighlightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Surface territory insights",
                    subtitle: "Get heatmaps, demographic overlays, and data-driven route recommendations."
                )

                FeatureHighlightRow(
                    icon: "figure.walk.circle.fill",
                    title: "Track your daily progress",
                    subtitle: "See how many doors you've hit and optimize your coverage in real time."
                )
            }

            Text("You can change this in Settings at any time.")
                .font(.obsidianFootnote)
                .foregroundColor(.textSecondary)
                .padding(.top, 8)
        }
    }

    private var notificationPermissionContent: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .frame(height: heroCardHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "bell.badge.fill")
                            .font(.displayHero)
                            .foregroundColor(.electricViolet)
                    )
            }

            VStack(spacing: 12) {
                FeatureHighlightRow(
                    icon: "alarm.fill",
                    title: "Never miss a follow-up",
                    subtitle: "Get timely reminders for callbacks, appointments, and scheduled check-ins."
                )

                FeatureHighlightRow(
                    icon: "calendar.badge.clock",
                    title: "Appointment confirmations",
                    subtitle: "Receive alerts before your scheduled appointments so you're always prepared."
                )

                FeatureHighlightRow(
                    icon: "sparkles",
                    title: "Smart territory alerts",
                    subtitle: "Get notified when you're near high-priority areas or hot leads."
                )
            }

            Text("You can customize notification preferences in Settings.")
                .font(.obsidianFootnote)
                .foregroundColor(.textSecondary)
                .padding(.top, 8)
        }
    }

    private var summaryContent: some View {
        let focusAreas = OnboardingProfile.FocusArea.allCases.filter { onboardingManager.profile.focusAreas.contains($0) }

        return VStack(spacing: 20) {
            SummaryCard(
                icon: onboardingManager.profile.salesGoal?.icon ?? "sparkles",
                title: onboardingManager.profile.salesGoal?.title ?? "Let’s build your workspace",
                subtitle: onboardingManager.profile.salesGoal?.subtitle ?? "We’ll fine tune your experience as you explore."
            )

            SummarySection(
                title: "What we'll spotlight",
                items: focusAreas.map { focus in
                    SummaryItem(
                        icon: focus.icon,
                        title: focus.title,
                        subtitle: focus.subtitle
                    )
                }
            )

            if let workflow = onboardingManager.profile.workflowStyle {
                SummarySection(
                    title: "Workflow fit",
                    items: [
                        SummaryItem(
                            icon: workflow.icon,
                            title: workflow.title,
                            subtitle: workflow.subtitle
                        )
                    ]
                )
            }
        }
    }

    private var navigationControls: some View {
        VStack(spacing: 16) {
            Button(action: {
                handleContinueButton()
            }) {
                HStack {
                    Text(buttonTitle)
                        .font(.obsidianAction)

                    Image(systemName: buttonIcon)
                        .font(.obsidianHeadline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .disabled(!onboardingManager.canAdvance(from: onboardingManager.currentPage))
            .opacity(onboardingManager.canAdvance(from: onboardingManager.currentPage) ? 1 : 0.45)
            .accessibilityIdentifier("onboardingContinueButton")

            if onboardingManager.currentPage.previous != nil {
                Button(action: {
                    onboardingManager.previousStep()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.obsidianSmall)
                        Text("Back")
                            .font(.obsidianCallout)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .padding(.horizontal, 20)
            }
        }
    }

    private var buttonTitle: String {
        switch onboardingManager.currentPage {
        case .summary:
            return "Finish & launch"
        case .locationPermission:
            return "Continue"
        case .notificationPermission:
            return "Continue"
        default:
            return "Continue"
        }
    }

    private var buttonIcon: String {
        switch onboardingManager.currentPage {
        case .summary:
            return "checkmark.seal.fill"
        case .locationPermission:
            return "location.fill"
        case .notificationPermission:
            return "bell.fill"
        default:
            return "arrow.right.circle.fill"
        }
    }

    private var buttonColor: (Color, Color) {
        switch onboardingManager.currentPage {
        case .locationPermission:
            return (Color.statusInterested, Color.electricViolet)
        case .notificationPermission:
            return (Color.electricViolet, Color.pink)
        default:
            return (Color.electricViolet, Color.electricViolet)
        }
    }

    private func handleContinueButton() {
        switch onboardingManager.currentPage {
        case .summary:
            onboardingManager.completeOnboarding()
        case .locationPermission:
            requestLocationPermission()
        case .notificationPermission:
            requestNotificationPermission()
        default:
            onboardingManager.nextStep()
        }
    }

    private func requestLocationPermission() {
        // Apple Guideline 5.1.1: Always show the system permission dialog
        // Check current authorization status
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            // REQUIRED: Request permission - this will show the system dialog
            // Users must see the system dialog and make a choice
            locationManager.requestPermission { newStatus in
                // This completion is called when the user responds to the dialog
                DispatchQueue.main.async {
                    print("📍 Location permission result: \(newStatus.rawValue)")

                    // Move to next step ONLY after user has seen and responded to dialog
                    self.onboardingManager.nextStep()
                }
            }

        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, move to next step
            print("✅ Location already authorized")
            onboardingManager.nextStep()

        case .denied, .restricted:
            // Permission previously denied or restricted
            // Show educational alert about enabling in Settings
            print("⚠️ Location permission denied or restricted")
            onboardingManager.nextStep()

        @unknown default:
            onboardingManager.nextStep()
        }
    }

    private func requestNotificationPermission() {
        // Apple Guideline 5.1.1: Always show the system permission dialog
        // Check current authorization status first
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    // REQUIRED: Request authorization - this will show the system dialog
                    // Users must see the system dialog and make a choice
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ Notification permission error: \(error.localizedDescription)")
                            }

                            if granted {
                                print("✅ Notification permission granted")
                            } else {
                                print("⚠️ Notification permission denied")
                            }

                            // Move to next step ONLY after user has seen and responded to dialog
                            onboardingManager.nextStep()
                        }
                    }

                case .authorized:
                    print("✅ Notifications already authorized")
                    onboardingManager.nextStep()

                case .denied, .provisional, .ephemeral:
                    print("⚠️ Notification permission denied or limited")
                    onboardingManager.nextStep()

                @unknown default:
                    onboardingManager.nextStep()
                }
            }
        }
    }
}

// MARK: - Components

private struct OnboardingProgressIndicator: View {
    let currentIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? Color.electricViolet : Color.textSecondary.opacity(0.2))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentIndex)
            }
        }
    }
}

private struct SelectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.obsidianHeadline)
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.obsidianCallout)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.obsidianHeadline)
                    .foregroundColor(isSelected ? accent : Color.textMuted)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? accent.opacity(0.85) : Color.obsidianBorder.opacity(0.55), lineWidth: isSelected ? 1.4 : 0.5)
                    )
                    .shadow(
                        color: isSelected ? accent.opacity(0.3) : Color.clear,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct MultiSelectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.obsidianHeadline)
                            .foregroundColor(accent)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.obsidianHeadline)
                        .foregroundColor(isSelected ? accent : Color.textMuted)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.obsidianCallout)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .font(.obsidianFootnote)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? accent.opacity(0.85) : Color.obsidianBorder.opacity(0.55), lineWidth: isSelected ? 1.4 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct FeatureHighlightRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isCompact = false

    var body: some View {
        HStack(spacing: isCompact ? 12 : 16) {
            ZStack {
                Circle()
                    .fill(Color.electricViolet.opacity(0.2))
                    .frame(width: isCompact ? 40 : 48, height: isCompact ? 40 : 48)
                Image(systemName: icon)
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.electricViolet)
            }

            VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(isCompact ? 12 : 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                )
        )
    }
}

private struct SummaryCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.electricViolet.opacity(0.14))
                    .frame(width: 96, height: 96)

                Image(systemName: icon)
                    .font(.displayMedium)
                    .foregroundColor(.electricViolet)
            }

            Text(title)
                .font(.obsidianHeadline)
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.obsidianBody)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                )
        )
    }
}

private struct SummarySection: View {
    let title: String
    let items: [SummaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.obsidianTitle)
                .foregroundColor(.textPrimary)

            ForEach(items) { item in
                SummaryItemView(item: item)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                )
        )
    }
}

private struct SummaryItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private struct SummaryItemView: View {
    let item: SummaryItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .font(.obsidianHeadline)
                .foregroundColor(Color.electricViolet)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.obsidianCallout)
                    .foregroundColor(.textPrimary)

                Text(item.subtitle)
                    .font(.obsidianFootnote)
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
    }
}

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        onChange(of: value, initial: false) { _, newValue in
            action(newValue)
        }
    }
}
