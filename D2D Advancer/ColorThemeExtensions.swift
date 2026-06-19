import SwiftUI
import UIKit

// MARK: - Obsidian Color System (Adaptive Light/Dark)

extension Color {
    // Base
    static let obsidianBlack = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
            : UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1) // #F7F8F9
    })
    static let obsidianSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1) // white
    })
    static let obsidianElevated = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
            : UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1) // #F3F4F6
    })
    static let obsidianBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.247, green: 0.247, blue: 0.275, alpha: 1)
            : UIColor(red: 0.878, green: 0.886, blue: 0.906, alpha: 1) // #E0E2E7
    })
    static let obsidianMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1)
            : UIColor(red: 0.612, green: 0.639, blue: 0.686, alpha: 1) // #9CA3AF
    })

    // Accent — Deep Gold (adaptive)
    static let electricViolet = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.831, green: 0.659, blue: 0.325, alpha: 1) // #D4A853 (bright on dark)
            : UIColor(red: 0.545, green: 0.392, blue: 0.098, alpha: 1) // #8B6419 (dark on light)
    })
    static let electricVioletLight = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.898, green: 0.776, blue: 0.525, alpha: 1) // #E5C686
            : UIColor(red: 0.620, green: 0.459, blue: 0.153, alpha: 1) // #9E7527
    })
    static let electricVioletDeep = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.659, green: 0.490, blue: 0.176, alpha: 1) // #A87D2D
            : UIColor(red: 0.424, green: 0.298, blue: 0.063, alpha: 1) // #6C4C10
    })
    static let dataCyan = Color(red: 0.024, green: 0.714, blue: 0.831)
    static let dataCyanMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 0.15)
            : UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 0.10)
    })

    // Status
    static let statusInterested = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let statusConverted = Color(red: 0.231, green: 0.510, blue: 0.965)
    static let statusNotHome = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let statusNotInterested = Color(red: 0.957, green: 0.247, blue: 0.369)
    static let statusNotContacted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1)
            : UIColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1) // #6B7280
    })

    // Text
    static let textPrimary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1) // #FAFAFA
            : UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1) // #111827
    })
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1) // #A1A1AA
            : UIColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1) // #6B7280
    })
    static let textMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1) // #71717A
            : UIColor(red: 0.612, green: 0.639, blue: 0.686, alpha: 1) // #9CA3AF
    })

    // Adaptive aliases (backward compatibility during migration)
    static let themeBackground = obsidianBlack
    static let themeSurface = obsidianSurface
    static let themeTextPrimary = textPrimary
    static let themeTextSecondary = textSecondary
    static let themePrimary = electricViolet
    static let themeSecondary = electricVioletDeep
    static let themeBorder = obsidianBorder
    static let themeShadow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor(red: 0, green: 0, blue: 0, alpha: 0.08)
    })
    static let themeAccent = electricVioletLight

    // Status aliases (backward compatibility)
    static let themeSuccess = statusInterested
    static let themeWarning = statusNotHome
    static let themeError = statusNotInterested
    static let themeInfo = statusConverted
}
