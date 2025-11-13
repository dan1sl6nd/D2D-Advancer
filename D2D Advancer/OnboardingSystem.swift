import SwiftUI
import CoreLocation
import UserNotifications

// MARK: - Onboarding Data Model

struct OnboardingProfile: Codable, Equatable {
    enum SalesGoal: String, CaseIterable, Codable, Identifiable {
        case organizePipeline
        case bookMoreAppointments
        case territoryPlanning
        case followUpAutomation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .organizePipeline: return "Organize my pipeline"
            case .bookMoreAppointments: return "Fill my appointment calendar"
            case .territoryPlanning: return "Optimize my knocking territory"
            case .followUpAutomation: return "Automate follow-ups"
            }
        }

        var subtitle: String {
            switch self {
            case .organizePipeline: return "Keep every lead, status, and note in one place"
            case .bookMoreAppointments: return "Schedule, track, and confirm appointments with ease"
            case .territoryPlanning: return "Surface the hottest streets and prioritize daily routes"
            case .followUpAutomation: return "Trigger reminders, scripts, and next steps automatically"
            }
        }

        var icon: String {
            switch self {
            case .organizePipeline: return "tray.full.fill"
            case .bookMoreAppointments: return "calendar.badge.plus"
            case .territoryPlanning: return "map.fill"
            case .followUpAutomation: return "bolt.fill"
            }
        }

        var accent: Color {
            switch self {
            case .organizePipeline: return .blue
            case .bookMoreAppointments: return .orange
            case .territoryPlanning: return .green
            case .followUpAutomation: return .purple
            }
        }
    }

    enum FocusArea: String, CaseIterable, Codable, Identifiable {
        case territoryInsights
        case automatedReminders
        case appointmentScheduling
        case messageTemplates
        case leadOrganization
        case calendarSync

        var id: String { rawValue }

        var title: String {
            switch self {
            case .territoryInsights: return "Territory insights"
            case .automatedReminders: return "Smart reminders"
            case .appointmentScheduling: return "Appointment scheduling"
            case .messageTemplates: return "Message templates"
            case .leadOrganization: return "Lead organization"
            case .calendarSync: return "Calendar sync"
            }
        }

        var subtitle: String {
            switch self {
            case .territoryInsights: return "Use heatmaps and demographic layers to prioritize doors"
            case .automatedReminders: return "Stay on top of every follow-up with auto reminders"
            case .appointmentScheduling: return "Track bookings and keep your day coordinated"
            case .messageTemplates: return "Send proven scripts and quick messages from the field"
            case .leadOrganization: return "Segment, filter, and track every lead status easily"
            case .calendarSync: return "Sync events with your calendar for one source of truth"
            }
        }

        var icon: String {
            switch self {
            case .territoryInsights: return "mappin.and.ellipse"
            case .automatedReminders: return "bell.badge.fill"
            case .appointmentScheduling: return "calendar"
            case .messageTemplates: return "text.bubble.fill"
            case .leadOrganization: return "square.stack.3d.up.fill"
            case .calendarSync: return "link"
            }
        }

        var accent: Color {
            switch self {
            case .territoryInsights: return .green
            case .automatedReminders: return .purple
            case .appointmentScheduling: return .orange
            case .messageTemplates: return .pink
            case .leadOrganization: return .blue
            case .calendarSync: return .teal
            }
        }
    }

    enum WorkflowStyle: String, CaseIterable, Codable, Identifiable {
        case structured
        case hustle
        case dataDriven

        var id: String { rawValue }

        var title: String {
            switch self {
            case .structured: return "Structured & scheduled"
            case .hustle: return "Fast-paced & flexible"
            case .dataDriven: return "Metrics obsessed"
            }
        }

        var subtitle: String {
            switch self {
            case .structured: return "Daily game plans, pre-built cadences, and repeatable systems"
            case .hustle: return "Quick lead capture, rapid follow-ups, and territory snapshots"
            case .dataDriven: return "Detailed dashboards, goal tracking, and performance alerts"
            }
        }

        var icon: String {
            switch self {
            case .structured: return "calendar.badge.clock"
            case .hustle: return "bolt.circle.fill"
            case .dataDriven: return "gauge.with.dots.needle.67percent"
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
        case .salesGoal: return "How do you sell today?"
        case .focusAreas: return "Where do you want an edge?"
        case .workflowStyle: return "How do you run your day?"
        case .locationPermission: return "Enable location tracking"
        case .notificationPermission: return "Stay on top of follow-ups"
        case .summary: return "Your custom launch plan"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "We'll learn how you work and tailor the experience so you get value on day one."
        case .salesGoal: return "Pick the outcome that matters most right now."
        case .focusAreas: return "Choose the areas where you need the most support. We'll surface the right tools."
        case .workflowStyle: return "Everyone sells differently. We'll match your workflow to the right features."
        case .locationPermission: return "We'll use your location to automatically log doors and surface territory insights."
        case .notificationPermission: return "Get timely reminders so you never miss a follow-up or appointment."
        case .summary: return "Here's how we'll configure D2D Advancer to help you win faster."
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

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.2),
                        Color.purple.opacity(0.12),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, max(geometry.safeAreaInsets.top + 12, 40))

                    ScrollView {
                        VStack(spacing: 24) {
                            content(for: onboardingManager.currentPage)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }

                    navigationControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom + 16, 32))
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(onboardingManager.currentPage.subtitle)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func content(for page: OnboardingPage) -> some View {
        switch page {
        case .welcome:
            welcomeContent
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
                }
            }

        case .focusAreas:
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick at least one priority (you can change these later).")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(OnboardingProfile.FocusArea.allCases) { focus in
                        MultiSelectionCard(
                            icon: focus.icon,
                            title: focus.title,
                            subtitle: focus.subtitle,
                            accent: focus.accent,
                            isSelected: onboardingManager.profile.focusAreas.contains(focus)
                        ) {
                            onboardingManager.toggleFocusArea(focus)
                        }
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
                        accent: .purple,
                        isSelected: onboardingManager.profile.workflowStyle == style
                    ) {
                        onboardingManager.selectWorkflowStyle(style)
                    }
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

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 72))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
            }

            VStack(spacing: 12) {
                FeatureHighlightRow(
                    icon: "mappin.circle.fill",
                    title: "Unlock smarter territory planning",
                    subtitle: "Use heatmaps and neighborhood scores to plan high-converting routes."
                )

                FeatureHighlightRow(
                    icon: "checkmark.circle.fill",
                    title: "Stay on top of every lead",
                    subtitle: "Capture doors, notes, and tasks so nothing slips through the cracks."
                )

                FeatureHighlightRow(
                    icon: "bolt.badge.clock",
                    title: "Automate tedious follow-ups",
                    subtitle: "Schedule reminders and send proven scripts in one tap."
                )
            }
        }
    }

    private var locationPermissionContent: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.18), Color.blue.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.green, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
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
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    private var notificationPermissionContent: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.18), Color.pink.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
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
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)
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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Image(systemName: buttonIcon)
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [buttonColor.0, buttonColor.1],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(18)
                .shadow(color: buttonColor.0.opacity(0.28), radius: 14, x: 0, y: 8)
            }
            .disabled(!onboardingManager.canAdvance(from: onboardingManager.currentPage))
            .opacity(onboardingManager.canAdvance(from: onboardingManager.currentPage) ? 1 : 0.45)

            if onboardingManager.currentPage.previous != nil {
                Button(action: {
                    onboardingManager.previousStep()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.12))
                    )
                }
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
            return (Color.green, Color.blue)
        case .notificationPermission:
            return (Color.purple, Color.pink)
        default:
            return (Color.blue, Color.purple)
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
                    .fill(
                        index <= currentIndex
                        ? LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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
                        .fill(accent.opacity(0.12))
                        .frame(width: 64, height: 64)

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isSelected ? accent : Color.secondary.opacity(0.4))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
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
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accent.opacity(0.16))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(accent)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? accent : Color.secondary.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
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

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(UIColor.secondarySystemBackground))
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
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

private struct SummarySection: View {
    let title: String
    let items: [SummaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            ForEach(items) { item in
                SummaryItemView(item: item)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemBackground))
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
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text(item.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
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
        if #available(iOS 17, *) {
            onChange(of: value, initial: false) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }
}
