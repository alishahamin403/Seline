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

    private var timer: Timer?

    private init() {
        self.selectedTheme = AppTheme(rawValue: selectedThemeRawValue) ?? .auto
        setupAutoThemeMonitoring()
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

        print("🕐 ThemeManager - Current hour: \(hour)")

        // Consider daytime as 6 AM to 6 PM
        let isDay = hour >= 6 && hour < 18
        print("🌓 ThemeManager - Is daytime: \(isDay)")
        return isDay
    }

    // Update the effective color scheme based on selected theme
    private func updateEffectiveColorScheme() {
        print("🎨 ThemeManager - Selected theme: \(selectedTheme.rawValue)")
        switch selectedTheme {
        case .auto:
            effectiveColorScheme = isDaytime() ? .light : .dark
            print("🎨 ThemeManager - Auto mode, effective scheme: \(effectiveColorScheme == .dark ? "dark" : "light")")
        case .light:
            effectiveColorScheme = .light
            print("🎨 ThemeManager - Light mode")
        case .dark:
            effectiveColorScheme = .dark
            print("🎨 ThemeManager - Dark mode")
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

    nonisolated deinit {
        Task { @MainActor in
            timer?.invalidate()
        }
    }
}