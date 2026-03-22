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
            if selectedTheme == .auto {
                scheduleNextAutoThemeBoundaryCheck()
            } else {
                cancelAutoThemeBoundaryCheck()
            }
        }
    }

    @Published var effectiveColorScheme: ColorScheme?
    @Published var systemColorScheme: ColorScheme? = nil {
        didSet {
            if selectedTheme == .auto {
                updateEffectiveColorScheme()
                scheduleNextAutoThemeBoundaryCheck()
            }
        }
    }

    private var autoThemeBoundaryTimer: Timer?
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

    // Get the preferred color scheme for SwiftUI
    // Returns nil for auto mode to let iOS use system setting
    func getPreferredColorScheme() -> ColorScheme? {
        switch selectedTheme {
        case .auto:
            return nil // Let system handle it - matches widget behavior
        case .light:
            return .light
        case .dark:
            return .dark
        }
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
            Task { @MainActor [weak self] in
                self?.detectSystemTheme() // Re-detect system theme when app becomes active
                self?.updateEffectiveColorScheme()
                self?.scheduleNextAutoThemeBoundaryCheck()
            }
        }

        // Listen for when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelAutoThemeBoundaryCheck()
            }
        }

        // Listen for significant time changes (timezone, date change, etc.)
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detectSystemTheme() // Re-detect system theme on time changes
                self?.updateEffectiveColorScheme()
                self?.scheduleNextAutoThemeBoundaryCheck()
            }
        }

        scheduleNextAutoThemeBoundaryCheck()
    }

    private func scheduleNextAutoThemeBoundaryCheck() {
        cancelAutoThemeBoundaryCheck()

        guard selectedTheme == .auto, systemColorScheme == nil else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let sixAM = calendar.date(byAdding: .hour, value: 6, to: startOfToday) ?? now
        let sixPM = calendar.date(byAdding: .hour, value: 18, to: startOfToday) ?? now

        let nextBoundary: Date
        if now < sixAM {
            nextBoundary = sixAM
        } else if now < sixPM {
            nextBoundary = sixPM
        } else {
            nextBoundary = calendar.date(byAdding: .day, value: 1, to: sixAM) ?? sixAM
        }

        let interval = max(1, nextBoundary.timeIntervalSince(now))
        autoThemeBoundaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateEffectiveColorScheme()
                self?.scheduleNextAutoThemeBoundaryCheck()
            }
        }
    }

    private func cancelAutoThemeBoundaryCheck() {
        autoThemeBoundaryTimer?.invalidate()
        autoThemeBoundaryTimer = nil
    }

    // Observe system color scheme changes (from widget or system settings)
    private func setupSystemThemeObserver() {
        systemThemeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detectSystemTheme()
            }
        }

        // Detect system theme on app launch
        detectSystemTheme()
    }

    // Detect the current system color scheme
    private func detectSystemTheme() {
        // Get the system appearance
        if #available(iOS 13.0, *) {
            // Try to get from connected scenes first
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }

            // If no key window, get any window
            let fallbackWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first

            let effectiveWindow = window ?? fallbackWindow
            let currentAppearance = effectiveWindow?.traitCollection.userInterfaceStyle ?? .unspecified

            switch currentAppearance {
            case .dark:
                systemColorScheme = .dark
            case .light:
                systemColorScheme = .light
            case .unspecified:
                // If unspecified, check user interface idiom
                // Default to light for unspecified
                systemColorScheme = .light
            @unknown default:
                systemColorScheme = .light
            }
        }
    }

    deinit {
        autoThemeBoundaryTimer?.invalidate()
        autoThemeBoundaryTimer = nil
        if let observer = systemThemeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
