import SwiftUI

// MARK: - Obsidian Color System

extension Color {
    // Base
    static let obsidianBlack = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let obsidianSurface = Color(red: 0.094, green: 0.094, blue: 0.106)
    static let obsidianElevated = Color(red: 0.153, green: 0.153, blue: 0.165)
    static let obsidianBorder = Color(red: 0.247, green: 0.247, blue: 0.275)
    static let obsidianMuted = Color(red: 0.443, green: 0.443, blue: 0.478)

    // Accent
    static let electricViolet = Color(red: 0.486, green: 0.228, blue: 0.929)
    static let electricVioletLight = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let electricVioletDeep = Color(red: 0.357, green: 0.129, blue: 0.714)
    static let dataCyan = Color(red: 0.024, green: 0.714, blue: 0.831)
    static let dataCyanMuted = Color(red: 0.024, green: 0.714, blue: 0.831).opacity(0.15)

    // Status
    static let statusInterested = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let statusConverted = Color(red: 0.231, green: 0.510, blue: 0.965)
    static let statusNotHome = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let statusNotInterested = Color(red: 0.957, green: 0.247, blue: 0.369)
    static let statusNotContacted = Color(red: 0.631, green: 0.631, blue: 0.667)

    // Text
    static let textPrimary = Color(red: 0.980, green: 0.980, blue: 0.980)
    static let textSecondary = Color(red: 0.631, green: 0.631, blue: 0.667)
    static let textMuted = Color(red: 0.443, green: 0.443, blue: 0.478)

    // Adaptive aliases (backward compatibility during migration)
    static let themeBackground = obsidianBlack
    static let themeSurface = obsidianSurface
    static let themeTextPrimary = textPrimary
    static let themeTextSecondary = textSecondary
    static let themePrimary = electricViolet
    static let themeSecondary = electricVioletDeep
    static let themeBorder = obsidianBorder
    static let themeShadow = Color.black
    static let themeAccent = electricVioletLight

    // Status aliases (backward compatibility)
    static let themeSuccess = statusInterested
    static let themeWarning = statusNotHome
    static let themeError = statusNotInterested
    static let themeInfo = statusConverted
}
