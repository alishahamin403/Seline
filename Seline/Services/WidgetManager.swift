import SwiftUI
import Combine

// MARK: - Widget Types

enum HomeWidgetType: String, CaseIterable, Codable, Identifiable {
    case dailyOverview = "daily_overview"
    case spending = "spending"
    case currentLocation = "current_location"
    case events = "events"
    case weather = "weather"
    case unreadEmails = "unread_emails"
    case pinnedNotes = "pinned_notes"
    case favoriteLocations = "favorite_locations"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dailyOverview: return "Daily Overview"
        case .spending: return "Monthly Spend"
        case .currentLocation: return "Current Location"
        case .events: return "Today's Events"
        case .weather: return "Weather"
        case .unreadEmails: return "Unread Emails"
        case .pinnedNotes: return "Pinned Notes"
        case .favoriteLocations: return "Favorite Locations"
        }
    }
    
    var icon: String {
        switch self {
        case .dailyOverview: return "sun.max.fill"
        case .spending: return "creditcard.fill"
        case .currentLocation: return "location.fill"
        case .events: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .unreadEmails: return "envelope.badge.fill"
        case .pinnedNotes: return "pin.fill"
        case .favoriteLocations: return "star.fill"
        }
    }
}

// MARK: - Widget Configuration

struct WidgetConfiguration: Codable, Identifiable, Equatable {
    let type: HomeWidgetType
    var isVisible: Bool
    var order: Int
    
    var id: String { type.rawValue }
    
    static func == (lhs: WidgetConfiguration, rhs: WidgetConfiguration) -> Bool {
        lhs.type == rhs.type && lhs.isVisible == rhs.isVisible && lhs.order == rhs.order
    }
}

// MARK: - Widget Manager

@MainActor
class WidgetManager: ObservableObject {
    static let shared = WidgetManager()
    
    private let storageKey = "home_widget_configurations"
    
    @Published var configurations: [WidgetConfiguration] = []
    @Published var isEditMode: Bool = false
    
    private init() {
        loadConfigurations()
    }
    
    // MARK: - Public Methods
    
    /// Get visible widgets sorted by order
    var visibleWidgets: [WidgetConfiguration] {
        var widgets = configurations
            .filter { $0.isVisible }
            .sorted { $0.order < $1.order }
        
        // CRITICAL: Ensure Quick Access (dailyOverview) is always first and visible
        // If it's not visible, make it visible
        if let dailyOverviewIndex = widgets.firstIndex(where: { $0.type == .dailyOverview }) {
            // Move it to the front
            let dailyOverview = widgets.remove(at: dailyOverviewIndex)
            widgets.insert(dailyOverview, at: 0)
        } else {
            // If it's not in the list, add it
            if let config = configurations.first(where: { $0.type == .dailyOverview }) {
                widgets.insert(config, at: 0)
            } else {
                // Create it if it doesn't exist
                let newConfig = WidgetConfiguration(type: .dailyOverview, isVisible: true, order: 0)
                configurations.append(newConfig)
                widgets.insert(newConfig, at: 0)
            }
        }
        
        return widgets
    }
    
    /// Get hidden widgets
    var hiddenWidgets: [WidgetConfiguration] {
        configurations
            .filter { !$0.isVisible }
            .sorted { $0.order < $1.order }
    }
    
    /// Toggle widget visibility
    func toggleVisibility(for type: HomeWidgetType) {
        // CRITICAL: Quick Access (dailyOverview) cannot be hidden
        if type == .dailyOverview {
            return
        }
        
        if let index = configurations.firstIndex(where: { $0.type == type }) {
            configurations[index].isVisible.toggle()
            saveConfigurations()
            HapticManager.shared.selection()
        }
    }
    
    /// Hide a widget
    func hideWidget(_ type: HomeWidgetType) {
        // CRITICAL: Quick Access (dailyOverview) cannot be hidden
        if type == .dailyOverview {
            return
        }
        
        if let index = configurations.firstIndex(where: { $0.type == type }) {
            configurations[index].isVisible = false
            saveConfigurations()
            HapticManager.shared.selection()
        }
    }
    
    /// Show a widget
    func showWidget(_ type: HomeWidgetType) {
        if let index = configurations.firstIndex(where: { $0.type == type }) {
            configurations[index].isVisible = true
            // Place it at the end of visible widgets
            let maxOrder = configurations.filter { $0.isVisible }.map { $0.order }.max() ?? 0
            configurations[index].order = maxOrder + 1
            normalizeOrder()
            saveConfigurations()
            HapticManager.shared.selection()
        }
    }
    
    /// Move widget from one position to another
    func moveWidget(from source: IndexSet, to destination: Int) {
        var visible = visibleWidgets
        visible.move(fromOffsets: source, toOffset: destination)
        
        // Update orders
        for (index, config) in visible.enumerated() {
            if let configIndex = configurations.firstIndex(where: { $0.type == config.type }) {
                configurations[configIndex].order = index
            }
        }
        
        saveConfigurations()
        HapticManager.shared.selection()
    }
    
    /// Move widget by dragging (for custom drag gesture)
    func moveWidget(_ type: HomeWidgetType, toIndex newIndex: Int) {
        // CRITICAL: Quick Access (dailyOverview) must always stay at position 0
        if type == .dailyOverview {
            return
        }
        
        let visible = visibleWidgets
        guard let currentIndex = visible.firstIndex(where: { $0.type == type }) else { return }
        
        var mutableVisible = visible
        let item = mutableVisible.remove(at: currentIndex)
        // Ensure we don't move anything to position 0 (reserved for Quick Access)
        let safeIndex = min(max(newIndex, 1), mutableVisible.count)
        mutableVisible.insert(item, at: safeIndex)
        
        // Update orders
        for (index, config) in mutableVisible.enumerated() {
            if let configIndex = configurations.firstIndex(where: { $0.type == config.type }) {
                configurations[configIndex].order = index
            }
        }
        
        saveConfigurations()
    }
    
    /// Enter edit mode
    func enterEditMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isEditMode = true
        }
        HapticManager.shared.medium()
    }
    
    /// Exit edit mode
    func exitEditMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isEditMode = false
        }
        HapticManager.shared.light()
    }
    
    /// Reset to default configuration
    func resetToDefaults() {
        configurations = Self.defaultConfigurations
        saveConfigurations()
        HapticManager.shared.success()
    }
    
    // MARK: - Private Methods
    
    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([WidgetConfiguration].self, from: data) {
            // Merge with defaults to handle new widget types
            var merged = saved
            for defaultConfig in Self.defaultConfigurations {
                if !merged.contains(where: { $0.type == defaultConfig.type }) {
                    merged.append(defaultConfig)
                }
            }
            configurations = merged
        } else {
            configurations = Self.defaultConfigurations
        }
    }
    
    private func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func normalizeOrder() {
        // Ensure visible widgets have sequential orders starting from 0
        let sortedVisible = configurations
            .filter { $0.isVisible }
            .sorted { $0.order < $1.order }
        
        for (index, config) in sortedVisible.enumerated() {
            if let configIndex = configurations.firstIndex(where: { $0.type == config.type }) {
                configurations[configIndex].order = index
            }
        }
    }
    
    // MARK: - Default Configuration
    
    private static var defaultConfigurations: [WidgetConfiguration] {
        [
            WidgetConfiguration(type: .dailyOverview, isVisible: true, order: 0),
            WidgetConfiguration(type: .spending, isVisible: true, order: 1),
            WidgetConfiguration(type: .currentLocation, isVisible: true, order: 2),
            WidgetConfiguration(type: .events, isVisible: true, order: 3),
            // New widgets - hidden by default, users can add them
            WidgetConfiguration(type: .weather, isVisible: false, order: 4),
            WidgetConfiguration(type: .unreadEmails, isVisible: false, order: 5),
            WidgetConfiguration(type: .pinnedNotes, isVisible: false, order: 6),
            WidgetConfiguration(type: .favoriteLocations, isVisible: false, order: 7)
        ]
    }
}

