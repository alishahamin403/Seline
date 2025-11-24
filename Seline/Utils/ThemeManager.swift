import SwiftUI

enum AppTheme: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .auto:
            return "clock"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto:
            return nil // Will be determined by time
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

    @AppStorage("selectedTheme") private var selectedThemeRawValue: String = AppTheme.auto.rawValue

    @Published var selectedTheme: AppTheme = .auto {
        didSet {
            selectedThemeRawValue = selectedTheme.rawValue
            updateEffectiveColorScheme()
        }
    }

    @Published var effectiveColorScheme: ColorScheme?
    @Published var systemColorScheme: ColorScheme? = nil {
        didSet {
            if selectedTheme == .auto {
                updateEffectiveColorScheme()
            }
        }
    }

    private var timer: Timer?
    private var systemThemeObserver: NSObjectProtocol?

    private init() {
        self.selectedTheme = AppTheme(rawValue: selectedThemeRawValue) ?? .auto
        setupAutoThemeMonitoring()
        setupSystemThemeObserver()
        updateEffectiveColorScheme()
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
    }

    // Helper to get the effective current color scheme
    func getCurrentEffectiveColorScheme() -> ColorScheme? {
        return effectiveColorScheme
    }

    // Determine if it's currently day or night based on time
    private func isDaytime() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // Consider daytime as 6 AM to 6 PM
        let isDay = hour >= 6 && hour < 18
        return isDay
    }

    // Update the effective color scheme based on selected theme
    private func updateEffectiveColorScheme() {
        switch selectedTheme {
        case .auto:
            // Prefer system theme if available (synced with widget), fallback to time-based
            if let systemTheme = systemColorScheme {
                effectiveColorScheme = systemTheme
            } else {
                effectiveColorScheme = isDaytime() ? .light : .dark
            }
        case .light:
            effectiveColorScheme = .light
        case .dark:
            effectiveColorScheme = .dark
        }
    }

    // Monitor time changes for auto theme
    private func setupAutoThemeMonitoring() {
        // Listen for when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateEffectiveColorScheme()
            self?.startTimer()
        }

        // Listen for when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopTimer()
        }

        // Listen for significant time changes (timezone, date change, etc.)
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateEffectiveColorScheme()
        }

        // Start timer for periodic checks
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        // Check every minute for theme changes
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateEffectiveColorScheme()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // Observe system color scheme changes (from widget or system settings)
    private func setupSystemThemeObserver() {
        systemThemeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.detectSystemTheme()
        }

        // Detect system theme on app launch
        detectSystemTheme()
    }

    // Detect the current system color scheme
    private func detectSystemTheme() {
        // Get the system appearance
        if #available(iOS 13.0, *) {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first

            let currentAppearance = window?.traitCollection.userInterfaceStyle ?? UITraitCollection().userInterfaceStyle

            switch currentAppearance {
            case .dark:
                systemColorScheme = .dark
            case .light:
                systemColorScheme = .light
            case .unspecified:
                systemColorScheme = nil
            @unknown default:
                systemColorScheme = nil
            }
        }
    }

    nonisolated deinit {
        Task { @MainActor in
            timer?.invalidate()
            if let observer = systemThemeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}