import SwiftUI

extension Color {
    // MARK: - Neutral Grayscale Palette
    // Keeps previous light/dark structure while removing blue tint.

    // Light mode
    static let wsLightBackground = Color.white // #FFFFFF
    static let wsLightSurface = Color.white // #FFFFFF
    static let wsLightSectionCard = Color.white // #FFFFFF
    static let wsLightInnerSurface = Color.white // #FFFFFF
    static let wsLightChip = Color.white // #FFFFFF
    static let wsLightChipStrong = Color.white // #FFFFFF
    static let wsLightBorder = Color(red: 0.890, green: 0.894, blue: 0.910) // #E3E4E8
    static let wsLightTextPrimary = Color(red: 0.102, green: 0.102, blue: 0.110) // #1A1A1C
    static let wsLightTextSecondary = Color(red: 0.400, green: 0.416, blue: 0.451) // #666A73

    // Dark mode
    static let wsDarkBackground = Color.black // #000000
    static let wsDarkSurface = Color(red: 0.078, green: 0.078, blue: 0.086) // #141416
    static let wsDarkSectionCard = Color(red: 0.094, green: 0.094, blue: 0.102) // #18181A
    static let wsDarkInnerSurface = Color(red: 0.114, green: 0.114, blue: 0.122) // #1D1D1F
    static let wsDarkChip = Color(red: 0.157, green: 0.157, blue: 0.169) // #28282B
    static let wsDarkChipStrong = Color(red: 0.196, green: 0.196, blue: 0.208) // #323235
    static let wsDarkBorder = Color.white.opacity(0.1)
    static let wsDarkTextPrimary = Color.white
    static let wsDarkTextSecondary = Color.white.opacity(0.7)

    // App-wide dynamic tokens
    static func appBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : emailLightBackground
    }

    static func appSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : .white
    }

    static func appSectionCard(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : .white
    }

    static func appInnerSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }

    static func appChip(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : emailLightChipIdle
    }

    static func appChipStrong(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : emailLightChipIdle
    }

    static func appBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : emailLightBorder
    }

    static func appTextPrimary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : emailLightTextPrimary
    }

    static func appTextSecondary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : emailLightTextSecondary
    }

    static func appMonochromeAccentFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.08)
    }

    static func appMonochromeAccentBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.12)
    }

    static func appMonochromeAmbientTint(
        _ colorScheme: ColorScheme,
        lightOpacity: Double,
        darkOpacity: Double
    ) -> Color {
        (colorScheme == .dark ? Color.white : Color.white)
            .opacity(colorScheme == .dark ? darkOpacity : lightOpacity)
    }

    // MARK: - Home Glass Tokens
    static let homeGlassAccent = Color(red: 0.98, green: 0.64, blue: 0.41)

    static func homeGlassBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : wsLightBackground
    }

    static func homeGlassCardTint(_ colorScheme: ColorScheme) -> Color {
        appSurface(colorScheme)
    }

    static func homeGlassInnerTint(_ colorScheme: ColorScheme) -> Color {
        appInnerSurface(colorScheme)
    }

    static func homeGlassBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? appBorder(colorScheme) : Color.black.opacity(0.045)
    }

    static func homeGlassInnerBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? appBorder(colorScheme) : Color.black.opacity(0.035)
    }

    static func searchResultsSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? wsDarkSectionCard : .white
    }

    static func searchResultsRowSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? wsDarkInnerSurface : Color(red: 0.965, green: 0.969, blue: 0.976)
    }

    // MARK: - Email Glass Tokens
    static let emailGlassAccent = Color(red: 0.94, green: 0.62, blue: 0.40)

    static func emailGlassBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : wsLightBackground
    }

    static func emailGlassCardTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : .white
    }

    static func emailGlassSectionTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.038) : .white
    }

    static func emailGlassInnerTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : .white
    }

    static func emailGlassBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07)
    }

    static func emailGlassInnerBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    static func emailGlassMutedText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.52)
    }

    // Primary Colors
    static let shadcnPrimary = Color(red: 0.22, green: 0.22, blue: 0.24)
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
    static let claudeAccent = Color.primary // Neutral black/white accent
    static let claudeInputDark = Color(red: 0.22, green: 0.21, blue: 0.20) // Darker input background
    static let claudeInputLight = Color(red: 0.95, green: 0.93, blue: 0.90) // Light cream input background
    static let claudeTextDark = Color(red: 0.95, green: 0.93, blue: 0.90) // Warm white text for dark mode
    static let claudeTextLight = Color(red: 0.15, green: 0.14, blue: 0.13) // Warm dark text for light mode

    // MARK: - Email Light Mode Tokens
    // Kept for compatibility across email/notes/receipt/map surfaces.
    static let emailLightBackground = wsLightBackground
    static let emailLightSurface = wsLightSurface
    static let emailLightSectionCard = wsLightSectionCard
    static let emailLightChipIdle = wsLightChip
    static let emailLightTextPrimary = wsLightTextPrimary
    static let emailLightTextSecondary = wsLightTextSecondary
    static let emailLightBorder = wsLightBorder

    // Background Colors
    static func shadcnBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.059, green: 0.059, blue: 0.063) : // #0F0F10
            emailLightBackground
    }

    static func shadcnCard(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color(red: 0.114, green: 0.114, blue: 0.122) : // #1D1D1F
            emailLightSectionCard
    }

    // Border Colors
    static func shadcnBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color.white.opacity(0.1) :
            emailLightBorder
    }

    // Text Colors
    static func shadcnForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color.white :
            emailLightTextPrimary
    }

    static func shadcnMuted(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color.white.opacity(0.7) :
            emailLightTextSecondary
    }

    static func shadcnMutedForeground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ?
            Color.white.opacity(0.7) :
            emailLightTextSecondary
    }

    // Accent Colors (neutral grayscale)
    static let shadcnAccent = Color(red: 0.231, green: 0.231, blue: 0.247) // #3B3B3F
    static let shadcnAccentLight = Color(red: 0.910, green: 0.910, blue: 0.922) // #E8E8EB
    static let shadcnAccentDark = Color(red: 0.133, green: 0.133, blue: 0.145) // #222225

    // Interactive States
    static let shadcnHover = Color(red: 0.631, green: 0.639, blue: 0.663) // #A1A3A9
    static let shadcnHoverDark = Color(red: 0.333, green: 0.333, blue: 0.353) // #55555A

    // Focus Ring
    static let shadcnRing = Color(red: 0.333, green: 0.333, blue: 0.353).opacity(0.3)
    
    // MARK: - Tile Background Colors
    // Standardized tile background color for consistent rounded square design
    static func shadcnTileBackground(_ colorScheme: ColorScheme) -> Color {
        appInnerSurface(colorScheme)
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

    func homeGlassCardStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 24,
        highlightStrength: Double = 1,
        usesPureLightFill: Bool = false
    ) -> some View {
        self
            .background(
                HomeGlassCardBackground(
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius,
                    highlightStrength: highlightStrength,
                    usesPureLightFill: usesPureLightFill
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.homeGlassBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.24) : Color.black.opacity(0.08),
                radius: colorScheme == .dark ? 10 : 20,
                x: 0,
                y: colorScheme == .dark ? 6 : 10
            )
    }

    func homeGlassInnerSurfaceStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 18
    ) -> some View {
        self
            .background(
                HomeGlassInnerSurface(
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.homeGlassInnerBorder(colorScheme), lineWidth: 1)
            )
    }

    func searchResultsCardStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 22
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.searchResultsSurface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.36) : Color.black.opacity(0.08),
                radius: colorScheme == .dark ? 16 : 12,
                x: 0,
                y: colorScheme == .dark ? 8 : 6
            )
    }

    func searchResultsRowStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 14
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.searchResultsRowSurface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.8 : 1), lineWidth: 1)
            )
    }

    func emailGlassHeroCardStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 24,
        highlightStrength: Double = 1
    ) -> some View {
        self
            .background(
                EmailGlassCardBackground(
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius,
                    highlightStrength: highlightStrength,
                    usesHeroHighlight: true
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.emailGlassBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.22) : Color.black.opacity(0.07),
                radius: colorScheme == .dark ? 10 : 18,
                x: 0,
                y: colorScheme == .dark ? 6 : 10
            )
    }

    func emailGlassSectionCardStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 22,
        highlightStrength: Double = 0.55
    ) -> some View {
        self
            .background(
                EmailGlassCardBackground(
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius,
                    highlightStrength: highlightStrength,
                    usesHeroHighlight: false
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.emailGlassBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.18) : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 8 : 14,
                x: 0,
                y: colorScheme == .dark ? 4 : 8
            )
    }

    func emailGlassInnerSurfaceStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 18
    ) -> some View {
        self
            .background(
                EmailGlassInnerSurface(
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.emailGlassInnerBorder(colorScheme), lineWidth: 1)
            )
    }

    func appAmbientCardStyle(
        colorScheme: ColorScheme,
        variant: AppAmbientBackgroundVariant = .topTrailing,
        cornerRadius: CGFloat = 24,
        highlightStrength: Double = 1
    ) -> some View {
        self
            .background(
                AppAmbientCardBackground(
                    colorScheme: colorScheme,
                    variant: variant,
                    cornerRadius: cornerRadius,
                    highlightStrength: highlightStrength
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.2) : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 10 : 18,
                x: 0,
                y: colorScheme == .dark ? 6 : 10
            )
    }

    func appAmbientInnerSurfaceStyle(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat = 18
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.appInnerSurface(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
    }
}

enum AppAmbientBackgroundVariant {
    case topTrailing
    case topLeading
    case bottomTrailing
    case bottomLeading
    case centerRight

    fileprivate var accentOffset: CGSize {
        switch self {
        case .topTrailing:
            return CGSize(width: 180, height: -250)
        case .topLeading:
            return CGSize(width: -185, height: -235)
        case .bottomTrailing:
            return CGSize(width: 188, height: 316)
        case .bottomLeading:
            return CGSize(width: -176, height: 304)
        case .centerRight:
            return CGSize(width: 196, height: -24)
        }
    }

    fileprivate var glowOffset: CGSize {
        switch self {
        case .topTrailing:
            return CGSize(width: -140, height: -228)
        case .topLeading:
            return CGSize(width: 132, height: -214)
        case .bottomTrailing:
            return CGSize(width: -124, height: -222)
        case .bottomLeading:
            return CGSize(width: 126, height: -214)
        case .centerRight:
            return CGSize(width: -150, height: -188)
        }
    }

    fileprivate var tertiaryOffset: CGSize {
        switch self {
        case .topTrailing:
            return CGSize(width: 96, height: 356)
        case .topLeading:
            return CGSize(width: -84, height: 346)
        case .bottomTrailing:
            return CGSize(width: -86, height: 248)
        case .bottomLeading:
            return CGSize(width: 98, height: 240)
        case .centerRight:
            return CGSize(width: -104, height: 298)
        }
    }

    fileprivate var cardAccentAlignment: Alignment {
        switch self {
        case .topTrailing, .centerRight:
            return .topTrailing
        case .topLeading:
            return .topLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .bottomLeading:
            return .bottomLeading
        }
    }

    fileprivate var cardAccentOffset: CGSize {
        switch self {
        case .topTrailing:
            return CGSize(width: 56, height: -46)
        case .topLeading:
            return CGSize(width: -56, height: -42)
        case .bottomTrailing:
            return CGSize(width: 56, height: 50)
        case .bottomLeading:
            return CGSize(width: -54, height: 52)
        case .centerRight:
            return CGSize(width: 60, height: -4)
        }
    }

    fileprivate var cardGlowAlignment: Alignment {
        switch self {
        case .topTrailing, .topLeading, .centerRight:
            return .bottomLeading
        case .bottomTrailing:
            return .topLeading
        case .bottomLeading:
            return .topTrailing
        }
    }

    fileprivate var cardGlowOffset: CGSize {
        switch self {
        case .topTrailing:
            return CGSize(width: -24, height: 92)
        case .topLeading:
            return CGSize(width: -12, height: 94)
        case .bottomTrailing:
            return CGSize(width: -20, height: -86)
        case .bottomLeading:
            return CGSize(width: 20, height: -86)
        case .centerRight:
            return CGSize(width: -18, height: 86)
        }
    }
}

struct HomeGlassBackgroundLayer: View {
    let colorScheme: ColorScheme

    var body: some View {
        Color.appBackground(colorScheme)
            .ignoresSafeArea()
    }
}

struct HomeGlassCardBackground: View {
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat
    let highlightStrength: Double
    let usesPureLightFill: Bool

    init(
        colorScheme: ColorScheme,
        cornerRadius: CGFloat,
        highlightStrength: Double,
        usesPureLightFill: Bool = false
    ) {
        self.colorScheme = colorScheme
        self.cornerRadius = cornerRadius
        self.highlightStrength = highlightStrength
        self.usesPureLightFill = usesPureLightFill
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseFillColor)
    }

    private var baseFillColor: Color {
        if colorScheme == .light {
            return usesPureLightFill ? .white : .white
        }
        return Color.homeGlassCardTint(colorScheme)
    }

}

struct HomeGlassInnerSurface: View {
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color.homeGlassInnerTint(colorScheme) : .white)
    }
}

struct EmailGlassBackgroundLayer: View {
    let colorScheme: ColorScheme

    var body: some View {
        Color.emailGlassBackground(colorScheme)
            .ignoresSafeArea()
    }
}

struct EmailGlassCardBackground: View {
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat
    let highlightStrength: Double
    let usesHeroHighlight: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? (usesHeroHighlight ? Color.emailGlassCardTint(colorScheme) : Color.emailGlassSectionTint(colorScheme))
                    : .white
            )
    }
}

struct EmailGlassInnerSurface: View {
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color.emailGlassInnerTint(colorScheme) : .white)
    }
}

struct AppAmbientBackgroundLayer: View {
    let colorScheme: ColorScheme
    let variant: AppAmbientBackgroundVariant

    init(
        colorScheme: ColorScheme,
        variant: AppAmbientBackgroundVariant = .topTrailing
    ) {
        self.colorScheme = colorScheme
        self.variant = variant
    }

    var body: some View {
        Color.appBackground(colorScheme)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct AppAmbientCardBackground: View {
    let colorScheme: ColorScheme
    let variant: AppAmbientBackgroundVariant
    let cornerRadius: CGFloat
    let highlightStrength: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.appSurface(colorScheme))
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
