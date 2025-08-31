//
//  ThemeManager.swift
//  Seline
//
//  Created by Claude on 2025-08-30.
//

import SwiftUI

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var selectedTheme: ThemeMode = .system {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
            applyTheme()
        }
    }
    
    @Published var isDarkMode: Bool = false
    
    private init() {
        // Load saved theme preference
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = ThemeMode(rawValue: savedTheme) {
            selectedTheme = theme
        }
        applyTheme()
        
        // Listen to system appearance changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func systemAppearanceChanged() {
        if selectedTheme == .system {
            updateCurrentAppearance()
        }
    }
    
    private func applyTheme() {
        DispatchQueue.main.async {
            switch self.selectedTheme {
            case .light:
                self.setAppearance(.light)
                self.isDarkMode = false
            case .dark:
                self.setAppearance(.dark)
                self.isDarkMode = true
            case .system:
                self.setAppearance(.unspecified)
                self.updateCurrentAppearance()
            }
        }
    }
    
    private func updateCurrentAppearance() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isDarkMode = windowScene.traitCollection.userInterfaceStyle == .dark
        }
    }
    
    private func setAppearance(_ style: UIUserInterfaceStyle) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

enum ThemeMode: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.striped.horizontal"
        }
    }
}