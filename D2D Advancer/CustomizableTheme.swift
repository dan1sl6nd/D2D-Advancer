import SwiftUI

// MARK: - Customizable Theme System
struct CustomizableTheme {
    // Primary Colors
    var primaryColor: Color = Color(red: 0.13, green: 0.31, blue: 0.54)
    var secondaryColor: Color = Color(red: 0.44, green: 0.50, blue: 0.57)
    var accentColor: Color = Color(red: 0.00, green: 0.48, blue: 0.80)
    
    // Status Colors
    var successColor: Color = Color(red: 0.18, green: 0.54, blue: 0.34)
    var warningColor: Color = Color(red: 0.85, green: 0.65, blue: 0.13)
    var errorColor: Color = Color(red: 0.78, green: 0.20, blue: 0.15)
    var infoColor: Color = Color(red: 0.12, green: 0.56, blue: 0.84)
    
    // Background Colors
    var backgroundColor: Color = Color(red: 0.98, green: 0.98, blue: 0.99)
    var surfaceColor: Color = Color.white
    
    // Text Colors
    var textPrimaryColor: Color = Color(red: 0.13, green: 0.16, blue: 0.20)
    var textSecondaryColor: Color = Color(red: 0.39, green: 0.45, blue: 0.52)
    
    // Border and Shadow
    var borderColor: Color = Color(red: 0.86, green: 0.89, blue: 0.92)
    var shadowColor: Color = Color.black.opacity(0.08)
    
    // Style Properties
    var cornerRadius: CGFloat = 8
    var shadowRadius: CGFloat = 4
    var buttonPadding: CGFloat = 12
}

// MARK: - Theme Presets for Quick Setup
extension CustomizableTheme {
    static let professional = CustomizableTheme(
        primaryColor: Color(red: 0.13, green: 0.31, blue: 0.54),
        secondaryColor: Color(red: 0.44, green: 0.50, blue: 0.57),
        accentColor: Color(red: 0.00, green: 0.48, blue: 0.80),
        successColor: Color(red: 0.18, green: 0.54, blue: 0.34),
        warningColor: Color(red: 0.85, green: 0.65, blue: 0.13),
        errorColor: Color(red: 0.78, green: 0.20, blue: 0.15),
        infoColor: Color(red: 0.12, green: 0.56, blue: 0.84),
        backgroundColor: Color(red: 0.98, green: 0.98, blue: 0.99),
        surfaceColor: Color.white,
        textPrimaryColor: Color(red: 0.13, green: 0.16, blue: 0.20),
        textSecondaryColor: Color(red: 0.39, green: 0.45, blue: 0.52),
        borderColor: Color(red: 0.86, green: 0.89, blue: 0.92),
        shadowColor: Color.black.opacity(0.08),
        cornerRadius: 8,
        shadowRadius: 4,
        buttonPadding: 12
    )
    
    static let modern = CustomizableTheme(
        primaryColor: Color(red: 0.20, green: 0.69, blue: 0.67),
        secondaryColor: Color(red: 0.54, green: 0.31, blue: 0.76),
        accentColor: Color(red: 0.96, green: 0.26, blue: 0.63),
        successColor: Color(red: 0.30, green: 0.84, blue: 0.44),
        warningColor: Color(red: 1.00, green: 0.76, blue: 0.03),
        errorColor: Color(red: 0.96, green: 0.26, blue: 0.21),
        infoColor: Color(red: 0.13, green: 0.69, blue: 0.98),
        backgroundColor: Color(red: 0.99, green: 0.99, blue: 1.00),
        surfaceColor: Color.white,
        textPrimaryColor: Color(red: 0.11, green: 0.11, blue: 0.13),
        textSecondaryColor: Color(red: 0.42, green: 0.45, blue: 0.50),
        borderColor: Color(red: 0.88, green: 0.91, blue: 0.94),
        shadowColor: Color.black.opacity(0.06),
        cornerRadius: 12,
        shadowRadius: 6,
        buttonPadding: 14
    )
    
    static let vibrant = CustomizableTheme(
        primaryColor: Color(red: 1.00, green: 0.34, blue: 0.13),
        secondaryColor: Color(red: 0.30, green: 0.84, blue: 0.44),
        accentColor: Color(red: 0.96, green: 0.87, blue: 0.00),
        successColor: Color(red: 0.13, green: 0.84, blue: 0.25),
        warningColor: Color(red: 1.00, green: 0.59, blue: 0.00),
        errorColor: Color(red: 0.96, green: 0.13, blue: 0.32),
        infoColor: Color(red: 0.00, green: 0.74, blue: 1.00),
        backgroundColor: Color(red: 1.00, green: 0.99, blue: 0.97),
        surfaceColor: Color(red: 1.00, green: 1.00, blue: 0.99),
        textPrimaryColor: Color(red: 0.15, green: 0.09, blue: 0.04),
        textSecondaryColor: Color(red: 0.52, green: 0.42, blue: 0.32),
        borderColor: Color(red: 0.92, green: 0.87, blue: 0.81),
        shadowColor: Color.black.opacity(0.12),
        cornerRadius: 10,
        shadowRadius: 8,
        buttonPadding: 16
    )
    
    static let minimal = CustomizableTheme(
        primaryColor: Color(red: 0.20, green: 0.20, blue: 0.22),
        secondaryColor: Color(red: 0.56, green: 0.56, blue: 0.58),
        accentColor: Color(red: 0.00, green: 0.48, blue: 0.99),
        successColor: Color(red: 0.20, green: 0.78, blue: 0.35),
        warningColor: Color(red: 1.00, green: 0.80, blue: 0.00),
        errorColor: Color(red: 1.00, green: 0.23, blue: 0.19),
        infoColor: Color(red: 0.35, green: 0.78, blue: 1.00),
        backgroundColor: Color(red: 1.00, green: 1.00, blue: 1.00),
        surfaceColor: Color.white,
        textPrimaryColor: Color(red: 0.09, green: 0.09, blue: 0.11),
        textSecondaryColor: Color(red: 0.42, green: 0.42, blue: 0.45),
        borderColor: Color(red: 0.90, green: 0.90, blue: 0.91),
        shadowColor: Color.black.opacity(0.04),
        cornerRadius: 4,
        shadowRadius: 2,
        buttonPadding: 10
    )
    
    static let corporate = CustomizableTheme(
        primaryColor: Color(red: 0.05, green: 0.24, blue: 0.47),
        secondaryColor: Color(red: 0.72, green: 0.53, blue: 0.04),
        accentColor: Color(red: 0.82, green: 0.18, blue: 0.18),
        successColor: Color(red: 0.13, green: 0.59, blue: 0.29),
        warningColor: Color(red: 0.96, green: 0.63, blue: 0.00),
        errorColor: Color(red: 0.86, green: 0.18, blue: 0.18),
        infoColor: Color(red: 0.05, green: 0.45, blue: 0.85),
        backgroundColor: Color(red: 0.97, green: 0.98, blue: 0.99),
        surfaceColor: Color(red: 0.99, green: 0.99, blue: 1.00),
        textPrimaryColor: Color(red: 0.05, green: 0.11, blue: 0.20),
        textSecondaryColor: Color(red: 0.31, green: 0.38, blue: 0.47),
        borderColor: Color(red: 0.84, green: 0.87, blue: 0.91),
        shadowColor: Color.black.opacity(0.10),
        cornerRadius: 2,
        shadowRadius: 3,
        buttonPadding: 12
    )
}

// MARK: - Color Extensions for Quick Access
extension Color {
    static func customThemed<T>(_ keyPath: KeyPath<CustomizableTheme, T>) -> T {
        CustomizableThemeManager.shared.currentTheme[keyPath: keyPath]
    }
}

// MARK: - Style Value Extensions
extension CGFloat {
    static var themeCornerRadius: CGFloat { CustomizableThemeManager.shared.currentTheme.cornerRadius }
    static var themeShadowRadius: CGFloat { CustomizableThemeManager.shared.currentTheme.shadowRadius }
    static var themeButtonPadding: CGFloat { CustomizableThemeManager.shared.currentTheme.buttonPadding }
}