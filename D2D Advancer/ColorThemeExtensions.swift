import SwiftUI

// Lightweight Color accessors that proxy the customizable theme
extension Color {
    static var themePrimary: Color { CustomizableThemeManager.shared.currentTheme.primaryColor }
    static var themeSecondary: Color { CustomizableThemeManager.shared.currentTheme.secondaryColor }
    static var themeAccent: Color { CustomizableThemeManager.shared.currentTheme.accentColor }
    static var themeBackground: Color { CustomizableThemeManager.shared.currentTheme.backgroundColor }
    static var themeSurface: Color { CustomizableThemeManager.shared.currentTheme.surfaceColor }
    static var themeTextPrimary: Color { CustomizableThemeManager.shared.currentTheme.textPrimaryColor }
    static var themeTextSecondary: Color { CustomizableThemeManager.shared.currentTheme.textSecondaryColor }
    static var themeBorder: Color { CustomizableThemeManager.shared.currentTheme.borderColor }
    static var themeSuccess: Color { CustomizableThemeManager.shared.currentTheme.successColor }
    static var themeWarning: Color { CustomizableThemeManager.shared.currentTheme.warningColor }
    static var themeError: Color { CustomizableThemeManager.shared.currentTheme.errorColor }
    static var themeInfo: Color { CustomizableThemeManager.shared.currentTheme.infoColor }
    static var themeShadow: Color { CustomizableThemeManager.shared.currentTheme.shadowColor }
}

