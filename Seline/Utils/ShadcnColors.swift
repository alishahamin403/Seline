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
    static let gmailDarkBackground = Color(red: 0.059, green: 0.059, blue: 0.059) // #0F0F0F (very dark gray)
    static let gmailDarkCard = Color(red: 0.235, green: 0.251, blue: 0.263) // #3c4043 (medium gray)
    static let gmailDarkCardAlt = Color(red: 0.196, green: 0.212, blue: 0.224) // #323639 (slightly darker gray)
    
    // MARK: - Claude-Style Colors
    // Inspired by Claude's warm, elegant chat interface
    static let claudeDarkBackground = Color(red: 0.176, green: 0.165, blue: 0.153) // #2D2A27 warm dark brown
    static let claudeLightBackground = Color(red: 0.961, green: 0.945, blue: 0.922) // #F5F1EB warm cream
    static let claudeAccent = Color(red: 0.878, green: 0.471, blue: 0.314) // #E07850 coral/orange
    static let claudeInputDark = Color(red: 0.22, green: 0.21, blue: 0.20) // Darker input background
    static let claudeInputLight = Color(red: 0.95, green: 0.93, blue: 0.90) // Light cream input background
    static let claudeTextDark = Color(red: 0.95, green: 0.93, blue: 0.90) // Warm white text for dark mode
    static let claudeTextLight = Color(red: 0.15, green: 0.14, blue: 0.13) // Warm dark text for light mode

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
    
    // MARK: - Tile Background Colors
    // Standardized tile background color for consistent rounded square design
    static func shadcnTileBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }
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
    
    // MARK: - Standardized Tile Design
    // Applies consistent rounded square design with standardized corner radius and fill color
    func shadcnTileStyle(colorScheme: ColorScheme) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 4 : 12,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.1) : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 2 : 6,
            x: 0,
            y: colorScheme == .dark ? 1 : 2
        )
    }
}

// MARK: - Shadcn Typography (using Geist font for consistency)
extension Font {
    static let shadcnTextXs = FontManager.geist(size: 12, weight: FontManager.FontWeight.regular) // text-xs
    static let shadcnTextSm = FontManager.geist(size: 14, weight: FontManager.FontWeight.regular) // text-sm
    static let shadcnTextBase = FontManager.geist(size: 16, weight: FontManager.FontWeight.regular) // text-base
    static let shadcnTextLg = FontManager.geist(size: 18, weight: FontManager.FontWeight.regular) // text-lg
    static let shadcnTextXl = FontManager.geist(size: 20, weight: FontManager.FontWeight.regular) // text-xl
    static let shadcnText2Xl = FontManager.geist(size: 24, weight: FontManager.FontWeight.regular) // text-2xl

    // Weight variants
    static let shadcnTextXsMedium = FontManager.geist(size: 12, weight: FontManager.FontWeight.medium)
    static let shadcnTextSmMedium = FontManager.geist(size: 14, weight: FontManager.FontWeight.medium)
    static let shadcnTextBaseMedium = FontManager.geist(size: 16, weight: FontManager.FontWeight.medium)
    static let shadcnTextLgSemibold = FontManager.geist(size: 18, weight: FontManager.FontWeight.semibold)
    static let shadcnText2XlBold = FontManager.geist(size: 24, weight: FontManager.FontWeight.bold)
}

// MARK: - Shadcn Spacing
struct ShadcnSpacing {
    static let xs: CGFloat = 4 // 1 unit
    static let sm: CGFloat = 8 // 2 units
    static let md: CGFloat = 16 // 4 units
    static let lg: CGFloat = 24 // 6 units
    static let xl: CGFloat = 32 // 8 units
    static let xxl: CGFloat = 48 // 12 units
    
    /// Horizontal margin from screen edge to tiles/boxes. Use app-wide for consistent layout.
    static let screenEdgeHorizontal: CGFloat = 8
}

// MARK: - Shadcn Border Radius
struct ShadcnRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}