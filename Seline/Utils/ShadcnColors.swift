import SwiftUI

extension Color {
    // MARK: - Custom Blue Color Palette
    // Colors: #d8ecf7, #84cae9, #65a2bc, #4c7c90, #345766, #1e353f, #09161b
    // Darker colors for light mode, lighter colors for dark mode

    // Primary Colors
    static let shadcnPrimary = Color(red: 0.20, green: 0.34, blue: 0.40) // #345766 (dark blue)
    static let shadcnPrimaryForeground = Color.white

    // MARK: - Gmail Dark Mode Colors
    // Inspired by Gmail's dark theme color palette
    static let gmailDarkBackground = Color(red: 0.102, green: 0.102, blue: 0.102) // #1a1a1a (very dark gray)
    static let gmailDarkCard = Color(red: 0.235, green: 0.251, blue: 0.263) // #3c4043 (medium gray)
    static let gmailDarkCardAlt = Color(red: 0.196, green: 0.212, blue: 0.224) // #323639 (slightly darker gray)

    // Background Colors
    static func shadcnBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.035, green: 0.086, blue: 0.106) : // #09161b (darkest blue)
            Color(red: 0.847, green: 0.925, blue: 0.969) // #d8ecf7 (lightest blue)
    }

    static func shadcnCard(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.118, green: 0.208, blue: 0.247) : // #1e353f (very dark blue)
            Color(red: 0.518, green: 0.792, blue: 0.914) // #84cae9 (medium blue)
    }

    // Border Colors
    static func shadcnBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.20, green: 0.34, blue: 0.40) : // #345766 (dark blue)
            Color(red: 0.396, green: 0.635, blue: 0.737) // #65a2bc (blue-gray)
    }

    // Text Colors
    static func shadcnForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color.white : // Pure white in dark mode
            Color(red: 0.035, green: 0.086, blue: 0.106) // #09161b (darkest blue)
    }

    static func shadcnMuted(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.396, green: 0.635, blue: 0.737) : // #65a2bc (blue-gray)
            Color(red: 0.298, green: 0.486, blue: 0.565) // #4c7c90 (dark blue-gray)
    }

    static func shadcnMutedForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.518, green: 0.792, blue: 0.914) : // #84cae9 (medium blue)
            Color(red: 0.298, green: 0.486, blue: 0.565) // #4c7c90 (dark blue-gray)
    }

    // Accent Colors (Blue variants)
    static let shadcnAccent = Color(red: 0.518, green: 0.792, blue: 0.914) // #84cae9 (medium blue)
    static let shadcnAccentLight = Color(red: 0.847, green: 0.925, blue: 0.969) // #d8ecf7 (lightest blue)
    static let shadcnAccentDark = Color(red: 0.118, green: 0.208, blue: 0.247) // #1e353f (very dark blue)

    // Interactive States
    static let shadcnHover = Color(red: 0.396, green: 0.635, blue: 0.737) // #65a2bc (blue-gray)
    static let shadcnHoverDark = Color(red: 0.298, green: 0.486, blue: 0.565) // #4c7c90 (dark blue-gray)

    // Focus Ring
    static let shadcnRing = Color(red: 0.518, green: 0.792, blue: 0.914).opacity(0.3) // #84cae9 with opacity
}

// MARK: - Shadcn Shadows
extension View {
    func shadcnShadowSm() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }

    func shadcnShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
    }

    func shadcnShadowMd() -> some View {
        self.shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 2)
    }

    func shadcnShadowLg() -> some View {
        self.shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 4)
    }
}

// MARK: - Shadcn Typography
extension Font {
    static let shadcnTextXs = Font.system(size: 12, weight: .regular) // text-xs
    static let shadcnTextSm = Font.system(size: 14, weight: .regular) // text-sm
    static let shadcnTextBase = Font.system(size: 16, weight: .regular) // text-base
    static let shadcnTextLg = Font.system(size: 18, weight: .regular) // text-lg
    static let shadcnTextXl = Font.system(size: 20, weight: .regular) // text-xl
    static let shadcnText2Xl = Font.system(size: 24, weight: .regular) // text-2xl

    // Weight variants
    static let shadcnTextSmMedium = Font.system(size: 14, weight: .medium)
    static let shadcnTextBaseMedium = Font.system(size: 16, weight: .medium)
    static let shadcnTextLgSemibold = Font.system(size: 18, weight: .semibold)
    static let shadcnText2XlBold = Font.system(size: 24, weight: .bold)
}

// MARK: - Shadcn Spacing
struct ShadcnSpacing {
    static let xs: CGFloat = 4 // 1 unit
    static let sm: CGFloat = 8 // 2 units
    static let md: CGFloat = 16 // 4 units
    static let lg: CGFloat = 24 // 6 units
    static let xl: CGFloat = 32 // 8 units
    static let xxl: CGFloat = 48 // 12 units
}

// MARK: - Shadcn Border Radius
struct ShadcnRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}