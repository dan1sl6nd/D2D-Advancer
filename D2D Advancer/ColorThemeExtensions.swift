import SwiftUI
import UIKit

// MARK: - Obsidian Color System (Adaptive Light / Dark)

extension Color {
    // Base
    static let obsidianBlack = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
            : UIColor(red: 0.96, green: 0.96, blue: 0.976, alpha: 1)
    })
    static let obsidianSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    })
    static let obsidianElevated = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.153, green: 0.153, blue: 0.165, alpha: 1)
            : UIColor(red: 0.94, green: 0.94, blue: 0.957, alpha: 1)
    })
    static let obsidianBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.247, green: 0.247, blue: 0.275, alpha: 1)
            : UIColor(red: 0.878, green: 0.878, blue: 0.898, alpha: 1)
    })
    static let obsidianMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1)
            : UIColor(red: 0.68, green: 0.68, blue: 0.714, alpha: 1)
    })

    // Accent
    static let electricViolet = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.486, green: 0.228, blue: 0.929, alpha: 1)
            : UIColor(red: 0.42, green: 0.18, blue: 0.85, alpha: 1)
    })
    static let electricVioletLight = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.655, green: 0.545, blue: 0.980, alpha: 1)
            : UIColor(red: 0.90, green: 0.85, blue: 0.98, alpha: 1)
    })
    static let electricVioletDeep = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.357, green: 0.129, blue: 0.714, alpha: 1)
            : UIColor(red: 0.30, green: 0.10, blue: 0.65, alpha: 1)
    })
    static let dataCyan = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 1)
            : UIColor(red: 0.0, green: 0.55, blue: 0.68, alpha: 1)
    })
    static let dataCyanMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 0.15)
            : UIColor(red: 0.0, green: 0.55, blue: 0.68, alpha: 0.15)
    })

    // Status
    static let statusInterested = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1)
            : UIColor(red: 0.05, green: 0.62, blue: 0.43, alpha: 1)
    })
    static let statusConverted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
            : UIColor(red: 0.18, green: 0.44, blue: 0.90, alpha: 1)
    })
    static let statusNotHome = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1)
            : UIColor(red: 0.88, green: 0.55, blue: 0.0, alpha: 1)
    })
    static let statusNotInterested = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.957, green: 0.247, blue: 0.369, alpha: 1)
            : UIColor(red: 0.87, green: 0.20, blue: 0.31, alpha: 1)
    })
    static let statusNotContacted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1)
            : UIColor(red: 0.50, green: 0.50, blue: 0.53, alpha: 1)
    })

    // Text
    static let textPrimary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1)
            : UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    })
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1)
            : UIColor(red: 0.38, green: 0.38, blue: 0.41, alpha: 1)
    })
    static let textMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1)
            : UIColor(red: 0.58, green: 0.58, blue: 0.61, alpha: 1)
    })

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
