import Foundation

final class TrackerEngine {
    static let shared = TrackerEngine()

    private init() {}

    func deriveState(
        for thread: TrackerThread,
        asOf: Date = Date()
    ) -> TrackerDerivedState {
        let snapshot = thread.memorySnapshot
        let warnings = validate(snapshot: snapshot)
        let recentChanges = Array(snapshot.changeLog.sorted(by: mostRecentFirst).prefix(6))
        let currentSummary = snapshot.normalizedSummaryText.trackerNonEmpty ?? "No tracked updates yet."
        let headline = recentChanges.first.flatMap { change in
            change.title?.trackerNonEmpty ?? change.content.trackerPreviewText
        }
            ?? currentSummary.trackerPreviewText
            ?? snapshot.quickFacts.first?.trackerPreviewText
            ?? "Tracker ready."
        let lastUpdatedAt = snapshot.lastUpdatedAt
            ?? snapshot.changeLog.map(\.effectiveAt).max()
            ?? thread.updatedAt

        return TrackerDerivedState(
            threadId: thread.id,
            asOf: asOf,
            ruleSummary: TrackerRuleSummaryBuilder.summary(for: snapshot),
            currentSummary: currentSummary,
            quickFacts: snapshot.quickFacts,
            recentChanges: recentChanges,
            changeCount: snapshot.changeLog.count,
            headline: headline,
            blockers: [],
            warnings: warnings,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    func projectedState(
        for proposedSnapshot: TrackerMemorySnapshot,
        on thread: TrackerThread,
        asOf: Date = Date()
    ) -> TrackerDerivedState {
        var projectedThread = thread
        projectedThread.title = proposedSnapshot.title.trackerNonEmpty ?? thread.title
        projectedThread.memorySnapshot = proposedSnapshot
        return deriveState(for: projectedThread, asOf: asOf)
    }

    func validate(snapshot: TrackerMemorySnapshot) -> [String] {
        var warnings: [String] = []

        if snapshot.version != 1 {
            warnings.append("This tracker snapshot uses a newer version than the app expects.")
        }
        if snapshot.normalizedRulesText.isEmpty {
            warnings.append("Tracker rules are empty.")
        }
        if snapshot.normalizedSummaryText.isEmpty {
            warnings.append("Tracker summary is empty.")
        }

        return warnings
    }

    private func mostRecentFirst(_ lhs: TrackerChange, _ rhs: TrackerChange) -> Bool {
        if lhs.effectiveAt == rhs.effectiveAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.effectiveAt > rhs.effectiveAt
    }
}
