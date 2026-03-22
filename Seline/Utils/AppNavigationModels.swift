import Foundation

enum PrimaryTab: String, CaseIterable, Hashable {
    case home
    case search
    case chat
    case notes
    case maps

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .maps: return "Places"
        }
    }

    var systemIcon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .chat: return "sparkles"
        case .notes: return "square.and.pencil"
        case .maps: return "map"
        }
    }

    var filledSystemIcon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .chat: return "sparkles"
        case .notes: return "square.and.pencil"
        case .maps: return "map.fill"
        }
    }

    var pageRoute: PageRoute {
        switch self {
        case .home: return .home
        case .search: return .search
        case .chat: return .chat
        case .notes: return .notes
        case .maps: return .maps
        }
    }
}

enum OverlayRoute: String, Identifiable {
    case plan
    case receipts
    case recurring
    case people
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .receipts: return "Receipts"
        case .recurring: return "Recurring"
        case .people: return "People"
        case .settings: return "Settings"
        }
    }
}

enum PageRoute: Hashable, CaseIterable {
    case home
    case search
    case plan
    case chat
    case notes
    case maps

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .plan: return "Plan"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .maps: return "Places"
        }
    }
}

enum SearchDestination: String, Hashable {
    case home
    case plan
    case search
    case chat
    case notes
    case maps

    var title: String {
        switch self {
        case .home: return "Home"
        case .plan: return "Plan"
        case .search: return "Search"
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .maps: return "Places"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .plan: return "calendar.badge.clock"
        case .search: return "magnifyingglass"
        case .chat: return "sparkles"
        case .notes: return "square.and.pencil"
        case .maps: return "map"
        }
    }
}
