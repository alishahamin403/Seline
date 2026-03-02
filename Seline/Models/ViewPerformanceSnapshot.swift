import Foundation

struct ViewPerformanceSnapshot: Identifiable, Codable, Hashable {
    let id: String
    let path: String
    let risk: String
    let observedSources: Int
    let timers: Int
    let notifications: Int
    let asyncReloads: Int
    let expensiveDerivedWork: String
    let recommendedFix: String

    init(
        path: String,
        risk: String,
        observedSources: Int,
        timers: Int,
        notifications: Int,
        asyncReloads: Int,
        expensiveDerivedWork: String,
        recommendedFix: String
    ) {
        self.id = path
        self.path = path
        self.risk = risk
        self.observedSources = observedSources
        self.timers = timers
        self.notifications = notifications
        self.asyncReloads = asyncReloads
        self.expensiveDerivedWork = expensiveDerivedWork
        self.recommendedFix = recommendedFix
    }
}
