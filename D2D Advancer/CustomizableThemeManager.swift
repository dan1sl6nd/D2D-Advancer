import SwiftUI
import Combine

/// Manages granular theme customization and persistence
class CustomizableThemeManager: ObservableObject {
    static let shared = CustomizableThemeManager()
    
    @Published var currentTheme: CustomizableTheme {
        didSet {
            saveTheme()
        }
    }
    
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
        let components = color.cgColor?.components ?? [0, 0, 0, 1]
        let colorData = [
            "red": Double(components[0]),
            "green": Double(components[1]),
            "blue": Double(components[2]),
            "alpha": Double(components.count > 3 ? components[3] : 1.0)
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: colorData) {
            userDefaults.set(data, forKey: themePrefix + key)
        }
    }
    
    private func loadColor(key: String, default defaultColor: Color) -> Color {
        guard let data = userDefaults.data(forKey: themePrefix + key),
              let colorData = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let red = colorData["red"],
              let green = colorData["green"],
              let blue = colorData["blue"],
              let alpha = colorData["alpha"] else {
            return defaultColor
        }
        
        return Color(red: red, green: green, blue: blue, opacity: alpha)
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

extension View {
    func surfaceCard() -> some View { modifier(SurfaceCardModifier()) }
    func elevatedCard(glow: Color = .electricViolet) -> some View { modifier(ElevatedCardModifier(glowColor: glow)) }
    func accentCard() -> some View { modifier(AccentCardModifier()) }

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
    static let displayLarge: Font = .system(size: 34, weight: .bold, design: .default)
    static let displayMedium: Font = .system(size: 28, weight: .bold, design: .default)

    // Content -- SF Pro Text for readable body content
    static let obsidianHeadline: Font = .system(size: 20, weight: .semibold, design: .default)
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
