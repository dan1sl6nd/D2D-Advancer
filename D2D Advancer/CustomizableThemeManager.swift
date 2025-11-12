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