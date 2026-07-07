import SwiftUI
import Combine

enum ObsidianLayout {
    static func finiteDimension(_ value: CGFloat, minimum: CGFloat = 0) -> CGFloat {
        guard value.isFinite else { return minimum }
        return max(value, minimum)
    }

    static func safeAreaTop(_ geometry: GeometryProxy, extra: CGFloat = 0, minimum: CGFloat = 0) -> CGFloat {
        finiteDimension(geometry.safeAreaInsets.top + extra, minimum: minimum)
    }

    static func safeAreaBottom(_ geometry: GeometryProxy, extra: CGFloat = 0, minimum: CGFloat = 0) -> CGFloat {
        finiteDimension(geometry.safeAreaInsets.bottom + extra, minimum: minimum)
    }
}

struct ThemeColorSnapshot: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

enum ThemeColorLocalStore {
    static func snapshot(fromCGColorComponents components: [CGFloat]?) -> ThemeColorSnapshot? {
        guard let components, let first = components.first else { return nil }

        switch components.count {
        case 1:
            let white = Double(first)
            return ThemeColorSnapshot(red: white, green: white, blue: white, alpha: 1)
        case 2:
            let white = Double(first)
            return ThemeColorSnapshot(red: white, green: white, blue: white, alpha: Double(components[1]))
        case 3:
            return ThemeColorSnapshot(
                red: Double(components[0]),
                green: Double(components[1]),
                blue: Double(components[2]),
                alpha: 1
            )
        default:
            return ThemeColorSnapshot(
                red: Double(components[0]),
                green: Double(components[1]),
                blue: Double(components[2]),
                alpha: Double(components[3])
            )
        }
    }

    static func encode(_ snapshot: ThemeColorSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    static func decode(from data: Data) throws -> ThemeColorSnapshot {
        try JSONDecoder().decode(ThemeColorSnapshot.self, from: data)
    }
}

/// Manages granular theme customization and persistence
class CustomizableThemeManager: ObservableObject {
    static let shared = CustomizableThemeManager()
    
    @Published var currentTheme: CustomizableTheme {
        didSet {
            saveTheme()
        }
    }

    @Published var lastErrorMessage: String?

    private let userDefaults = UserDefaults.standard
    private let themePrefix = "customTheme_"
    
    private init() {
        // Initialize with default theme first
        self.currentTheme = CustomizableTheme.professional
        // Then load the saved theme
        self.currentTheme = loadTheme()
    }
    
    // MARK: - Individual Color Setters
    func setPrimaryColor(_ color: Color) {
        currentTheme.primaryColor = color
        objectWillChange.send()
    }
    
    func setSecondaryColor(_ color: Color) {
        currentTheme.secondaryColor = color
        objectWillChange.send()
    }
    
    func setAccentColor(_ color: Color) {
        currentTheme.accentColor = color
        objectWillChange.send()
    }
    
    func setSuccessColor(_ color: Color) {
        currentTheme.successColor = color
        objectWillChange.send()
    }
    
    func setWarningColor(_ color: Color) {
        currentTheme.warningColor = color
        objectWillChange.send()
    }
    
    func setErrorColor(_ color: Color) {
        currentTheme.errorColor = color
        objectWillChange.send()
    }
    
    func setInfoColor(_ color: Color) {
        currentTheme.infoColor = color
        objectWillChange.send()
    }
    
    func setBackgroundColor(_ color: Color) {
        currentTheme.backgroundColor = color
        objectWillChange.send()
    }
    
    func setSurfaceColor(_ color: Color) {
        currentTheme.surfaceColor = color
        objectWillChange.send()
    }
    
    func setTextPrimaryColor(_ color: Color) {
        currentTheme.textPrimaryColor = color
        objectWillChange.send()
    }
    
    func setTextSecondaryColor(_ color: Color) {
        currentTheme.textSecondaryColor = color
        objectWillChange.send()
    }
    
    func setBorderColor(_ color: Color) {
        currentTheme.borderColor = color
        objectWillChange.send()
    }
    
    func setShadowColor(_ color: Color) {
        currentTheme.shadowColor = color
        objectWillChange.send()
    }
    
    // MARK: - Style Property Setters
    func setCornerRadius(_ radius: CGFloat) {
        currentTheme.cornerRadius = max(0, min(radius, 20)) // Clamp between 0-20
        objectWillChange.send()
    }
    
    func setShadowRadius(_ radius: CGFloat) {
        currentTheme.shadowRadius = max(0, min(radius, 15)) // Clamp between 0-15
        objectWillChange.send()
    }
    
    func setButtonPadding(_ padding: CGFloat) {
        currentTheme.buttonPadding = max(4, min(padding, 24)) // Clamp between 4-24
        objectWillChange.send()
    }
    
    // MARK: - Preset Loading
    func loadPreset(_ preset: CustomizableTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = preset
        }
    }
    
    // MARK: - Reset Functions
    func resetToDefault() {
        loadPreset(.professional)
    }
    
    func resetColorsOnly() {
        let professional = CustomizableTheme.professional
        currentTheme.primaryColor = professional.primaryColor
        currentTheme.secondaryColor = professional.secondaryColor
        currentTheme.accentColor = professional.accentColor
        currentTheme.successColor = professional.successColor
        currentTheme.warningColor = professional.warningColor
        currentTheme.errorColor = professional.errorColor
        currentTheme.infoColor = professional.infoColor
        currentTheme.backgroundColor = professional.backgroundColor
        currentTheme.surfaceColor = professional.surfaceColor
        currentTheme.textPrimaryColor = professional.textPrimaryColor
        currentTheme.textSecondaryColor = professional.textSecondaryColor
        currentTheme.borderColor = professional.borderColor
        currentTheme.shadowColor = professional.shadowColor
        objectWillChange.send()
    }
    
    func resetStylesOnly() {
        let professional = CustomizableTheme.professional
        currentTheme.cornerRadius = professional.cornerRadius
        currentTheme.shadowRadius = professional.shadowRadius
        currentTheme.buttonPadding = professional.buttonPadding
        objectWillChange.send()
    }
    
    // MARK: - Persistence
    private func saveTheme() {
        // Save individual properties as encoded data
        
        // Save colors as RGB components
        saveColor(currentTheme.primaryColor, key: "primaryColor")
        saveColor(currentTheme.secondaryColor, key: "secondaryColor")
        saveColor(currentTheme.accentColor, key: "accentColor")
        saveColor(currentTheme.successColor, key: "successColor")
        saveColor(currentTheme.warningColor, key: "warningColor")
        saveColor(currentTheme.errorColor, key: "errorColor")
        saveColor(currentTheme.infoColor, key: "infoColor")
        saveColor(currentTheme.backgroundColor, key: "backgroundColor")
        saveColor(currentTheme.surfaceColor, key: "surfaceColor")
        saveColor(currentTheme.textPrimaryColor, key: "textPrimaryColor")
        saveColor(currentTheme.textSecondaryColor, key: "textSecondaryColor")
        saveColor(currentTheme.borderColor, key: "borderColor")
        saveColor(currentTheme.shadowColor, key: "shadowColor")
        
        // Save style properties
        userDefaults.set(currentTheme.cornerRadius, forKey: themePrefix + "cornerRadius")
        userDefaults.set(currentTheme.shadowRadius, forKey: themePrefix + "shadowRadius")
        userDefaults.set(currentTheme.buttonPadding, forKey: themePrefix + "buttonPadding")
    }
    
    private func loadTheme() -> CustomizableTheme {
        var theme = CustomizableTheme.professional
        
        // Load colors
        theme.primaryColor = loadColor(key: "primaryColor", default: theme.primaryColor)
        theme.secondaryColor = loadColor(key: "secondaryColor", default: theme.secondaryColor)
        theme.accentColor = loadColor(key: "accentColor", default: theme.accentColor)
        theme.successColor = loadColor(key: "successColor", default: theme.successColor)
        theme.warningColor = loadColor(key: "warningColor", default: theme.warningColor)
        theme.errorColor = loadColor(key: "errorColor", default: theme.errorColor)
        theme.infoColor = loadColor(key: "infoColor", default: theme.infoColor)
        theme.backgroundColor = loadColor(key: "backgroundColor", default: theme.backgroundColor)
        theme.surfaceColor = loadColor(key: "surfaceColor", default: theme.surfaceColor)
        theme.textPrimaryColor = loadColor(key: "textPrimaryColor", default: theme.textPrimaryColor)
        theme.textSecondaryColor = loadColor(key: "textSecondaryColor", default: theme.textSecondaryColor)
        theme.borderColor = loadColor(key: "borderColor", default: theme.borderColor)
        theme.shadowColor = loadColor(key: "shadowColor", default: theme.shadowColor)
        
        // Load style properties
        let cornerRadius = userDefaults.object(forKey: themePrefix + "cornerRadius") as? CGFloat
        let shadowRadius = userDefaults.object(forKey: themePrefix + "shadowRadius") as? CGFloat
        let buttonPadding = userDefaults.object(forKey: themePrefix + "buttonPadding") as? CGFloat
        
        if let cornerRadius = cornerRadius { theme.cornerRadius = cornerRadius }
        if let shadowRadius = shadowRadius { theme.shadowRadius = shadowRadius }
        if let buttonPadding = buttonPadding { theme.buttonPadding = buttonPadding }
        
        return theme
    }

    func reloadThemeFromUserDefaults() {
        currentTheme = loadTheme()
        objectWillChange.send()
    }
    
    private func saveColor(_ color: Color, key: String) {
        guard let snapshot = ThemeColorLocalStore.snapshot(fromCGColorComponents: color.cgColor?.components) else {
            let message = "Theme color \(key) could not be saved because it has no color components."
            lastErrorMessage = message
            print("⚠️ \(message)")
            return
        }

        do {
            let data = try ThemeColorLocalStore.encode(snapshot)
            userDefaults.set(data, forKey: themePrefix + key)
            lastErrorMessage = nil
        } catch {
            let message = "Theme color \(key) could not be saved: \(error.localizedDescription)"
            lastErrorMessage = message
            print("⚠️ \(message)")
        }
    }
    
    private func loadColor(key: String, default defaultColor: Color) -> Color {
        guard let data = userDefaults.data(forKey: themePrefix + key) else {
            return defaultColor
        }

        do {
            let snapshot = try ThemeColorLocalStore.decode(from: data)
            lastErrorMessage = nil
            return Color(
                red: snapshot.red,
                green: snapshot.green,
                blue: snapshot.blue,
                opacity: snapshot.alpha
            )
        } catch {
            let message = "Theme color \(key) could not be loaded: \(error.localizedDescription)"
            lastErrorMessage = message
            print("⚠️ \(message)")
            return defaultColor
        }
    }
}

// MARK: - Theme Environment Key
struct CustomizableThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: CustomizableTheme = CustomizableTheme.professional
}

extension EnvironmentValues {
    var customizableTheme: CustomizableTheme {
        get { self[CustomizableThemeEnvironmentKey.self] }
        set { self[CustomizableThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Themed Modifier
struct CustomizableThemedModifier: ViewModifier {
    @ObservedObject private var themeManager = CustomizableThemeManager.shared
    
    func body(content: Content) -> some View {
        content
            .environment(\.customizableTheme, themeManager.currentTheme)
            .accentColor(themeManager.currentTheme.accentColor)
    }
}

extension View {
    /// Applies the current customizable theme to the view
    func customThemed() -> some View {
        self.modifier(CustomizableThemedModifier())
    }
    
    /// Applies custom themed card styling
    func customThemedCard() -> some View {
        self
            .padding()
            .background(Color.themeSurface)
            .cornerRadius(.themeCornerRadius)
            .shadow(
                color: Color.themeShadow,
                radius: .themeShadowRadius,
                x: 0,
                y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: .themeCornerRadius)
                    .stroke(Color.themeBorder, lineWidth: 0.5)
            )
    }
    
    /// Applies custom themed button styling
    func customThemedButton(_ variant: CustomThemedButtonVariant = .primary) -> some View {
        self.buttonStyle(CustomThemedButtonStyle(variant: variant))
    }
}

// MARK: - Custom Button Styles
enum CustomThemedButtonVariant {
    case primary
    case secondary
    case outline
    case ghost
    case danger
    case success
}

struct CustomThemedButtonStyle: ButtonStyle {
    let variant: CustomThemedButtonVariant
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, .themeButtonPadding)
            .padding(.vertical, .themeButtonPadding * 0.75)
            .background(backgroundColorForVariant(configuration.isPressed))
            .foregroundColor(foregroundColorForVariant)
            .overlay(
                RoundedRectangle(cornerRadius: .themeCornerRadius)
                    .stroke(borderColorForVariant, lineWidth: borderWidth)
            )
            .cornerRadius(.themeCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var borderWidth: CGFloat {
        variant == .outline ? 1.5 : 0
    }
    
    private func backgroundColorForVariant(_ isPressed: Bool) -> Color {
        let baseColor: Color
        
        switch variant {
        case .primary:
            baseColor = Color.themePrimary
        case .secondary:
            baseColor = Color.themeSecondary
        case .outline, .ghost:
            baseColor = Color.clear
        case .danger:
            baseColor = Color.themeError
        case .success:
            baseColor = Color.themeSuccess
        }
        
        return isPressed ? baseColor.opacity(0.8) : baseColor
    }
    
    private var foregroundColorForVariant: Color {
        switch variant {
        case .primary, .secondary, .danger, .success:
            return .white
        case .outline:
            return Color.themePrimary
        case .ghost:
            return Color.themeTextPrimary
        }
    }
    
    private var borderColorForVariant: Color {
        switch variant {
        case .outline:
            return Color.themePrimary
        default:
            return Color.clear
        }
    }
}

struct ObsidianEditorSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.5), lineWidth: 0.5)
            )
            .foregroundColor(.textPrimary)
    }
}

extension View {
    func obsidianEditorSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(ObsidianEditorSurfaceModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Obsidian Header View

struct ObsidianHeaderView: View {
    let title: String
    var titleAccessibilityIdentifier: String? = nil
    var trailing: AnyView? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, titleAccessibilityIdentifier: String? = nil) {
        self.title = title
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
    }

    init(
        _ title: String,
        titleAccessibilityIdentifier: String? = nil,
        @ViewBuilder trailing: () -> some View
    ) {
        self.title = title
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            titleText
            Spacer()
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Color.obsidianBackground(for: colorScheme))
    }

    @ViewBuilder
    private var titleText: some View {
        let text = Text(title)
            .font(.displayMedium)
            .foregroundColor(.textPrimary)

        if let titleAccessibilityIdentifier {
            text.accessibilityIdentifier(titleAccessibilityIdentifier)
        } else {
            text
        }
    }
}

// MARK: - Shared Obsidian Screen Components

struct ObsidianSectionCard<Content: View>: View {
    let title: String
    let icon: String
    var subtitle: String?
    var accentColor: Color = .electricViolet
    @ViewBuilder var content: Content

    init(
        title: String,
        icon: String,
        subtitle: String? = nil,
        accentColor: Color = .electricViolet,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.obsidianCallout)
                    .foregroundColor(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

struct ObsidianEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            Image(systemName: icon)
                .font(.displayMedium)
                .foregroundColor(Color.electricViolet)
                .frame(width: 88, height: 88)
                .background(Color.electricViolet.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 8) {
                Text(title)
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 34)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon ?? "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .padding(.horizontal, 42)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ObsidianCompactIconButton: View {
    let icon: String
    let accessibilityLabel: String
    var accentColor: Color = .electricViolet
    var backgroundColor: Color? = nil
    var foregroundColor: Color? = nil
    var borderColor: Color? = nil
    var accessibilityIdentifier: String? = nil
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ObsidianIconButtonFace(
                icon: icon,
                accentColor: accentColor,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                borderColor: borderColor,
                size: size
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

private struct ObsidianToolbarIconButton: View {
    let icon: String
    let accessibilityLabel: String
    var accentColor: Color = .electricViolet
    var backgroundColor: Color? = nil
    var foregroundColor: Color? = nil
    var borderColor: Color? = nil
    var accessibilityIdentifier: String? = nil
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ObsidianIconButtonFace(
                icon: icon,
                accentColor: accentColor,
                backgroundColor: backgroundColor,
                foregroundColor: foregroundColor,
                borderColor: borderColor,
                size: size
            )
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

private struct ObsidianIconButtonFace: View {
    let icon: String
    let accentColor: Color
    var backgroundColor: Color?
    var foregroundColor: Color?
    var borderColor: Color?
    let size: CGFloat

    var body: some View {
        let resolvedBackground = backgroundColor ?? accentColor.opacity(0.14)
        let resolvedForeground = foregroundColor ?? accentColor
        let resolvedBorder = borderColor ?? accentColor.opacity(0.22)

        ZStack {
            Circle()
                .fill(resolvedBackground)

            Image(systemName: icon)
                .font(.obsidianCallout)
                .fontWeight(.semibold)
                .foregroundColor(resolvedForeground)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(resolvedBorder, lineWidth: 0.5)
        )
        .clipShape(Circle())
        .contentShape(Circle())
    }
}

struct ObsidianBackButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var accessibilityLabel: String = "Back"
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        ObsidianToolbarIconButton(
            icon: "chevron.left",
            accessibilityLabel: accessibilityLabel,
            accentColor: backFill,
            backgroundColor: backFill,
            foregroundColor: backForeground,
            borderColor: backBorder,
            accessibilityIdentifier: accessibilityIdentifier,
            size: 44,
            action: action
        )
    }

    private var backFill: Color {
        colorScheme == .dark ? .white : Color.textPrimary
    }

    private var backForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var backBorder: Color {
        Color.clear
    }
}

struct ObsidianCloseButton: View {
    var accessibilityLabel: String = "Close"
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        ObsidianToolbarIconButton(
            icon: "xmark",
            accessibilityLabel: accessibilityLabel,
            accentColor: Color.textPrimary,
            backgroundColor: .clear,
            foregroundColor: Color.textPrimary,
            borderColor: .clear,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}

struct ObsidianScreenTitle: View {
    let title: String
    var subtitle: String?
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.electricViolet)
                    .frame(width: 38, height: 38)
                    .background(Color.electricViolet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.displayMedium)
                    .foregroundColor(Color.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.obsidianBody)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct ObsidianStatusBanner: View {
    let icon: String
    let title: String
    var message: String?
    var tint: Color = .electricViolet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.obsidianCallout)
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }
}

struct ObsidianIconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 46
    var filled = false

    private var cornerRadius: CGFloat {
        min(14, size * 0.3)
    }

    var body: some View {
        Image(systemName: icon)
            .font(size >= 42 ? .obsidianAction : .obsidianCallout)
            .fontWeight(.semibold)
            .foregroundColor(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(filled ? tint : tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ObsidianDetailRow<Accessory: View>: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var valueColor: Color = .textPrimary
    var valueLineLimit: Int?
    private let accessory: (() -> Accessory)?

    init(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        valueColor: Color = .textPrimary,
        valueLineLimit: Int? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
        self.valueColor = valueColor
        self.valueLineLimit = valueLineLimit
        self.accessory = accessory
    }

    init(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        valueColor: Color = .textPrimary,
        valueLineLimit: Int? = nil
    ) where Accessory == EmptyView {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
        self.valueColor = valueColor
        self.valueLineLimit = valueLineLimit
        self.accessory = nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(icon: icon, tint: tint, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                Text(value)
                    .font(.obsidianCallout)
                    .foregroundColor(valueColor)
                    .lineLimit(valueLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let accessory {
                accessory()
            }
        }
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
    }
}

struct ObsidianActionTile: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    var isEnabled = true
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ObsidianIconTile(icon: icon, tint: isEnabled ? tint : Color.textMuted, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.obsidianCallout)
                        .foregroundColor(isEnabled ? Color.textPrimary : Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(2)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
}

struct ObsidianBottomActionBar<PrimaryLabel: View, SecondaryLabel: View>: View {
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    var isPrimaryDisabled = false
    var primaryAccessibilityIdentifier: String?
    var secondaryAccessibilityIdentifier: String?
    @ViewBuilder var primaryLabel: PrimaryLabel
    @ViewBuilder var secondaryLabel: SecondaryLabel
    @Environment(\.colorScheme) private var colorScheme

    init(
        isPrimaryDisabled: Bool = false,
        primaryAccessibilityIdentifier: String? = nil,
        secondaryAccessibilityIdentifier: String? = nil,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void,
        @ViewBuilder primaryLabel: () -> PrimaryLabel,
        @ViewBuilder secondaryLabel: () -> SecondaryLabel
    ) {
        self.isPrimaryDisabled = isPrimaryDisabled
        self.primaryAccessibilityIdentifier = primaryAccessibilityIdentifier
        self.secondaryAccessibilityIdentifier = secondaryAccessibilityIdentifier
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.primaryLabel = primaryLabel()
        self.secondaryLabel = secondaryLabel()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: secondaryAction) {
                secondaryLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianSecondaryButtonStyle())
            .accessibilityIdentifierIfPresent(secondaryAccessibilityIdentifier)

            Button(action: primaryAction) {
                primaryLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ObsidianPrimaryButtonStyle())
            .disabled(isPrimaryDisabled)
            .opacity(isPrimaryDisabled ? 0.55 : 1)
            .accessibilityIdentifierIfPresent(primaryAccessibilityIdentifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.obsidianBackground(for: colorScheme)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: -3)
        )
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifierIfPresent(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

// MARK: - Obsidian Card Modifiers

struct SurfaceCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
    }
}

struct ElevatedCardModifier: ViewModifier {
    var glowColor: Color = .electricViolet
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
            .shadow(color: glowColor.opacity(0.2), radius: 16, x: 0, y: 4)
    }
}

struct AccentCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                LinearGradient(
                    colors: [.electricViolet, .electricVioletDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Obsidian chip modifier for tags and filters (replaces GlassChipModifier).
struct ObsidianChipModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
    }
}

/// Obsidian gradient button modifier (replaces GlassButtonModifier).
struct ObsidianGradientButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .background(
                LinearGradient(
                    colors: [.electricViolet, .electricVioletDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .electricViolet.opacity(0.25), radius: 8)
    }
}

/// Obsidian floating action button modifier (replaces GlassFloatingButtonModifier).
struct ObsidianFloatingButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(
                LinearGradient(
                    colors: [.electricViolet, .electricVioletDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
            .shadow(color: .electricViolet.opacity(0.30), radius: 12)
    }
}

// MARK: - Obsidian Card & Modifier View Extensions

enum ObsidianNavigationChromePolicy {
    static func toolbarColorScheme(for colorScheme: ColorScheme) -> ColorScheme {
        colorScheme
    }
}

struct ObsidianInlineNavigationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea(edges: .top))
            .toolbarBackground(Color.obsidianBackground(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(
                ObsidianNavigationChromePolicy.toolbarColorScheme(for: colorScheme),
                for: .navigationBar
            )
            .tint(Color.electricViolet)
    }
}

private struct ObsidianPushedNavigationHeader<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var backButtonAccessibilityIdentifier: String?
    let trailing: Trailing
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ObsidianBackButton(accessibilityIdentifier: backButtonAccessibilityIdentifier) {
                onBack()
            }
            .frame(width: 44, height: 44)
            .accessibilityIdentifierIfPresent(backButtonAccessibilityIdentifier)

            Text(title)
                .font(.displayMedium)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea(edges: .top))
    }
}

struct ObsidianPushedNavigationModifier<Trailing: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var backButtonAccessibilityIdentifier: String?
    let trailing: Trailing
    var onBack: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ObsidianPushedNavigationHeader(
                    title: title,
                    backButtonAccessibilityIdentifier: backButtonAccessibilityIdentifier,
                    trailing: trailing
                ) {
                    if let onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            }
    }
}

private struct ObsidianScreenBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color.obsidianBackground(for: colorScheme).ignoresSafeArea())
    }
}

private struct ObsidianModalBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let background = Color.obsidianBackground(for: colorScheme)

        content
            .background(background.ignoresSafeArea())
            .presentationBackground(background)
    }
}

private struct ObsidianListScreenModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.obsidianBackground(for: colorScheme))
            .tint(Color.electricViolet)
    }
}

extension View {
    func surfaceCard() -> some View { modifier(SurfaceCardModifier()) }
    func elevatedCard(glow: Color = .electricViolet) -> some View { modifier(ElevatedCardModifier(glowColor: glow)) }
    func accentCard() -> some View { modifier(AccentCardModifier()) }

    func obsidianScreenBackground() -> some View {
        modifier(ObsidianScreenBackgroundModifier())
    }

    func obsidianModalBackground() -> some View {
        modifier(ObsidianModalBackgroundModifier())
    }

    func obsidianListScreen() -> some View {
        modifier(ObsidianListScreenModifier())
    }

    func obsidianListRow() -> some View {
        listRowBackground(Color.obsidianSurface)
            .listRowSeparatorTint(Color.obsidianBorder.opacity(0.6))
            .foregroundColor(Color.textPrimary)
    }

    func obsidianInlineNavigation() -> some View {
        modifier(ObsidianInlineNavigationModifier())
    }

    func obsidianPushedNavigation(_ title: String, backButtonAccessibilityIdentifier: String? = nil) -> some View {
        modifier(
            ObsidianPushedNavigationModifier(
                title: title,
                backButtonAccessibilityIdentifier: backButtonAccessibilityIdentifier,
                trailing: EmptyView(),
                onBack: nil
            )
        )
    }

    func obsidianPushedNavigation(
        _ title: String,
        backButtonAccessibilityIdentifier: String? = nil,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(
            ObsidianPushedNavigationModifier(
                title: title,
                backButtonAccessibilityIdentifier: backButtonAccessibilityIdentifier,
                trailing: EmptyView(),
                onBack: onBack
            )
        )
    }

    func obsidianPushedNavigation<Trailing: View>(
        _ title: String,
        backButtonAccessibilityIdentifier: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            ObsidianPushedNavigationModifier(
                title: title,
                backButtonAccessibilityIdentifier: backButtonAccessibilityIdentifier,
                trailing: trailing(),
                onBack: nil
            )
        )
    }

    func obsidianPushedNavigation<Trailing: View>(
        _ title: String,
        backButtonAccessibilityIdentifier: String? = nil,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            ObsidianPushedNavigationModifier(
                title: title,
                backButtonAccessibilityIdentifier: backButtonAccessibilityIdentifier,
                trailing: trailing(),
                onBack: onBack
            )
        )
    }

    /// Backward-compatible alias: `.glassCard()` now maps to `.surfaceCard()`.
    func glassCard() -> some View { modifier(SurfaceCardModifier()) }

    /// Backward-compatible alias: `.glassChip()` now maps to Obsidian chip style.
    func glassChip() -> some View { modifier(ObsidianChipModifier()) }

    /// Backward-compatible alias: `.glassButton()` now maps to Obsidian gradient button.
    func glassButton() -> some View { modifier(ObsidianGradientButtonModifier()) }

    /// Backward-compatible alias: `.glassFloatingButton()` now maps to Obsidian floating button.
    func glassFloatingButton() -> some View { modifier(ObsidianFloatingButtonModifier()) }
}

// MARK: - Obsidian Button Styles

struct ObsidianPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                LinearGradient(
                    colors: [.electricViolet, .electricVioletDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .electricViolet.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ObsidianSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ObsidianGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ObsidianDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.statusNotInterested)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.statusNotInterested.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Obsidian Status Badge

struct ObsidianStatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - Obsidian Spacing

extension CGFloat {
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let spaceXXL: CGFloat = 32
}

// MARK: - Obsidian Text Field Style

struct ObsidianTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.obsidianBorder, lineWidth: 1)
            )
            .foregroundColor(.textPrimary)
    }
}

// MARK: - Obsidian Typography System

extension Font {
    // Display -- SF Pro Display for hero text and big numbers
    static let displayHero: Font = .system(size: 42, weight: .bold, design: .rounded)
    static let displayLarge: Font = .system(size: 34, weight: .bold, design: .default)
    static let displayMedium: Font = .system(size: 28, weight: .bold, design: .default)

    // Content -- SF Pro Text for readable body content
    static let obsidianHeadline: Font = .system(size: 20, weight: .semibold, design: .default)
    static let obsidianSubheadline: Font = .system(size: 20, weight: .bold, design: .rounded)
    static let obsidianTitle: Font = .system(size: 17, weight: .semibold, design: .default)
    static let obsidianBody: Font = .system(size: 15, weight: .regular, design: .default)
    static let obsidianCaption: Font = .system(size: 13, weight: .medium, design: .default)
    static let micro: Font = .system(size: 11, weight: .medium, design: .default)
    static let obsidianAction: Font = .system(size: 18, weight: .semibold, design: .default)
    static let obsidianCallout: Font = .system(size: 16, weight: .semibold, design: .default)
    static let obsidianFootnote: Font = .system(size: 13, weight: .medium, design: .default)
    static let obsidianSmall: Font = .system(size: 12, weight: .medium, design: .default)
    static let nano: Font = .system(size: 10, weight: .medium, design: .default)

    // Migration aliases
    static let themeLargeTitle: Font = .displayMedium
    static let themeTitle: Font = .obsidianHeadline
    static let themeHeadline: Font = .obsidianTitle
    static let themeBody: Font = .obsidianBody
    static let themeCaption: Font = .obsidianCaption
    static let themeSmall: Font = .micro
}

// MARK: - Micro Label Style

struct MicroLabelStyle: ViewModifier {
    var color: Color = .textMuted
    func body(content: Content) -> some View {
        content
            .font(.micro)
            .foregroundColor(color)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

extension View {
    func microLabel(color: Color = .textMuted) -> some View {
        modifier(MicroLabelStyle(color: color))
    }
}
