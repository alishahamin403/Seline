import Foundation

enum RefreshReason: String, CaseIterable, Hashable {
    case initialLoad
    case manualRefresh
    case appBecameActive
    case visitHistoryChanged
    case emailDataChanged
    case noteDataChanged
    case taskDataChanged
    case locationDataChanged
}

@MainActor
final class PageRefreshCoordinator {
    struct PageState: Equatable {
        var lastVisibleAt: Date?
        var lastValidatedAt: Date?
        var dirtyReasons: Set<RefreshReason> = []
    }

    static let shared = PageRefreshCoordinator()

    private var pageStates: [PageRoute: PageState] = [:]

    private init() {
        for page in PageRoute.allCases {
            pageStates[page] = PageState()
        }
    }

    func pageBecameVisible(_ page: PageRoute) {
        mutate(page) { state in
            state.lastVisibleAt = Date()
        }
        log("visible", page: page, details: nil)
    }

    func markDirty(_ page: PageRoute, reason: RefreshReason) {
        mutate(page) { state in
            state.dirtyReasons.insert(reason)
        }
        log("dirty", page: page, details: reason.rawValue)
    }

    func markDirty<S: Sequence>(_ pages: S, reason: RefreshReason) where S.Element == PageRoute {
        for page in pages {
            markDirty(page, reason: reason)
        }
    }

    func shouldRevalidate(_ page: PageRoute, maxAge: TimeInterval) -> Bool {
        let state = pageStates[page] ?? PageState()

        if !state.dirtyReasons.isEmpty {
            return true
        }

        guard let lastValidatedAt = state.lastValidatedAt else {
            return true
        }

        return Date().timeIntervalSince(lastValidatedAt) >= maxAge
    }

    func markValidated(_ page: PageRoute) {
        mutate(page) { state in
            state.lastValidatedAt = Date()
            state.dirtyReasons.removeAll()
        }
        log("validated", page: page, details: nil)
    }

    func isDirty(_ page: PageRoute) -> Bool {
        !(pageStates[page]?.dirtyReasons.isEmpty ?? true)
    }

    func defaultMaxAge(for page: PageRoute) -> TimeInterval {
        switch page {
        case .home:
            return 60
        case .search:
            return .infinity
        case .plan:
            return 30
        case .chat:
            return .infinity
        case .notes:
            return 300
        case .maps:
            return .infinity
        }
    }

    private func mutate(_ page: PageRoute, update: (inout PageState) -> Void) {
        var state = pageStates[page] ?? PageState()
        update(&state)
        pageStates[page] = state
    }

    private func log(_ event: String, page: PageRoute, details: String?) {
#if DEBUG
        if let details {
            print("📄 PageRefreshCoordinator[\(event)] \(page.title): \(details)")
        } else {
            print("📄 PageRefreshCoordinator[\(event)] \(page.title)")
        }
#endif
    }
}
