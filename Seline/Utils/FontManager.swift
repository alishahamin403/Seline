import SwiftUI

struct FontManager {

    // MARK: - Font Names
    private static let geistSansRegular = "GeistSans-Regular"
    private static let geistSansMedium = "GeistSans-Medium"
    private static let geistSansSemibold = "GeistSans-Semibold"
    private static let geistSansBold = "GeistSans-Bold"

    // MARK: - Font Weights
    enum FontWeight {
        case regular
        case medium
        case semibold
        case bold

        var fontName: String {
            switch self {
            case .regular: return FontManager.geistSansRegular
            case .medium: return FontManager.geistSansMedium
            case .semibold: return FontManager.geistSansSemibold
            case .bold: return FontManager.geistSansBold
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    // MARK: - Font Sizes
    enum FontSize: CGFloat {
        case caption = 10
        case small = 12
        case body = 14
        case title3 = 16
        case title2 = 18
        case title1 = 20
        case large = 24
        case extraLarge = 32
    }

    // MARK: - Font Creation Methods
    static func geist(size: FontSize, weight: FontWeight = .regular) -> Font {
        // Try custom font first, fallback to system font if not available
        if let customFont = UIFont(name: weight.fontName, size: size.rawValue) {
            return Font(customFont)
        } else {
            // Fallback to system font with similar characteristics
            return .system(size: size.rawValue, weight: weight.systemWeight, design: .default)
        }
    }

    static func geist(size: CGFloat, weight: FontWeight = .regular) -> Font {
        // Try custom font first, fallback to system font if not available
        if let customFont = UIFont(name: weight.fontName, size: size) {
            return Font(customFont)
        } else {
            // Fallback to system font with similar characteristics
            return .system(size: size, weight: weight.systemWeight, design: .default)
        }
    }
}

// MARK: - Convenience Extensions
extension Font {

    // MARK: - Common UI Element Fonts
    static let geistCaption = FontManager.geist(size: .caption, weight: .regular)
    static let geistSmall = FontManager.geist(size: .small, weight: .regular)
    static let geistBody = FontManager.geist(size: .body, weight: .regular)
    static let geistBodyMedium = FontManager.geist(size: .body, weight: .medium)
    static let geistTitle3 = FontManager.geist(size: .title3, weight: .semibold)
    static let geistTitle2 = FontManager.geist(size: .title2, weight: .semibold)
    static let geistTitle1 = FontManager.geist(size: .title1, weight: .bold)
    static let geistLarge = FontManager.geist(size: .large, weight: .bold)
    static let geistExtraLarge = FontManager.geist(size: .extraLarge, weight: .bold)

    // MARK: - Tab Bar and Navigation
    static let geistTabTitle = FontManager.geist(size: .caption, weight: .medium)
    static let geistNavTitle = FontManager.geist(size: .title2, weight: .semibold)

    // MARK: - Buttons
    static let geistButton = FontManager.geist(size: .body, weight: .medium)
    static let geistButtonLarge = FontManager.geist(size: .title3, weight: .semibold)
}