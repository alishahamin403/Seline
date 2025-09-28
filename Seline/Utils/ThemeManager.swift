import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system:
            return "gear"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("selectedTheme") private var selectedThemeRawValue: String = AppTheme.system.rawValue

    @Published var selectedTheme: AppTheme = .system {
        didSet {
            selectedThemeRawValue = selectedTheme.rawValue
        }
    }

    private init() {
        self.selectedTheme = AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
    }

    // Helper to get the effective current color scheme
    func getCurrentEffectiveColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch selectedTheme {
        case .system:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}