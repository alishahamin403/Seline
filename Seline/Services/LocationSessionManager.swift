import Foundation
import PostgREST

// MARK: - Session Info Model

struct SessionInfo {
    var sessionId: UUID
    var savedPlaceId: UUID
    var userId: UUID
    var openTime: Date
    var closeTime: Date?
    var visitCount: Int = 1
    var confidenceScore: Double = 1.0
    var mergeReasons: [String] = []

    var isOpen: Bool {
        closeTime == nil
    }

    var durationMinutes: Int {
        let duration = (closeTime ?? Date()).timeIntervalSince(openTime)
        return Int(duration / 60)
    }
}

// MARK: - LocationSessionManager

@MainActor
class LocationSessionManager {
    static let shared = LocationSessionManager()

    private var activeSessions: [UUID: SessionInfo] = [:] // [sessionId: session]
    private let sessionCacheTTL: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Session Creation

    /// Create a new session for a visit
    func createSession(
        for placeId: UUID,
        userId: UUID
    ) -> UUID {
        let sessionId = UUID()
        let session = SessionInfo(
            sessionId: sessionId,
            savedPlaceId: placeId,
            userId: userId,
            openTime: Date()
        )
        activeSessions[sessionId] = session
        // DEBUG: Commented out to reduce console spam
        // print("📋 Created new session: \(sessionId.uuidString) for place: \(placeId.uuidString)")
        return sessionId
    }

    // MARK: - Session Management

    /// Add a visit to an existing session
    func addVisitToSession(_ sessionId: UUID, visitRecord: LocationVisitRecord) {
        if var session = activeSessions[sessionId] {
            session.visitCount += 1
            session.mergeReasons.append(visitRecord.mergeReason ?? "")

            // Update minimum confidence (use lowest confidence in session)
            if let confidence = visitRecord.confidenceScore {
                session.confidenceScore = min(session.confidenceScore, confidence)
            }

            activeSessions[sessionId] = session
            print("✅ Added visit to session: \(visitRecord.id.uuidString)")
            print("   Session \(sessionId.uuidString) now has \(session.visitCount) visits")
        } else {
            print("⚠️ Session not found: \(sessionId.uuidString)")
        }
    }

    /// Close a session
    func closeSession(_ sessionId: UUID) {
        if var session = activeSessions[sessionId] {
            session.closeTime = Date()
            activeSessions[sessionId] = session

            // Remove from memory after TTL
            DispatchQueue.main.asyncAfter(deadline: .now() + sessionCacheTTL) { [weak self] in
                self?.activeSessions.removeValue(forKey: sessionId)
            }

            print("✅ Closed session: \(sessionId.uuidString)")
            print("   Duration: \(session.durationMinutes) minutes, Visits: \(session.visitCount)")
        }
    }

    /// Get session info
    func getSession(_ sessionId: UUID) -> SessionInfo? {
        return activeSessions[sessionId]
    }

    /// Get all active sessions
    func getActiveSessions() -> [SessionInfo] {
        return activeSessions.values.filter { $0.isOpen }
    }

    // MARK: - Session Recovery (App Restart)

    /// Recover incomplete sessions from Supabase on app launch
    func recoverSessionsOnAppLaunch(for userId: UUID) async {
        // DEBUG: Commented out to reduce console spam
        // print("\n🔍 ===== RECOVERING SESSIONS ON APP LAUNCH =====")

        guard let user = SupabaseManager.shared.getCurrentUser() else {
            print("⚠️ No authenticated user")
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()

            // Find all incomplete visits (exit_time IS NULL) grouped by session_id
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .limit(20)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Group by session_id
            let grouped = Dictionary(grouping: visits) { $0.sessionId ?? UUID() }

            for (sessionId, sessionVisits) in grouped {
                // Find the first incomplete visit in this session
                if let incompleteVisit = sessionVisits.first(where: { $0.exitTime == nil }) {
                    let hoursSinceEntry = Date().timeIntervalSince(incompleteVisit.entryTime) / 3600

                    print("\n📋 Found session: \(sessionId.uuidString)")
                    print("   Open since: \(incompleteVisit.entryTime)")
                    print("   Hours open: \(String(format: "%.1f", hoursSinceEntry))")

                    if hoursSinceEntry > 24 {
                        // Auto-close stale sessions
                        print("⚠️  Session open >24 hours, auto-closing...")
                        await autoCloseSession(sessionId, userId: userId)
                    } else if hoursSinceEntry > 4 {
                        // Show user alert for long-running sessions
                        print("⚠️  Session open >4 hours, user should confirm...")
                        // In real app, show alert here
                        activeSessions[sessionId] = SessionInfo(
                            sessionId: sessionId,
                            savedPlaceId: incompleteVisit.savedPlaceId,
                            userId: userId,
                            openTime: incompleteVisit.entryTime,
                            visitCount: sessionVisits.count
                        )
                    } else {
                        // Restore active session
                        print("✅ Restoring active session...")
                        activeSessions[sessionId] = SessionInfo(
                            sessionId: sessionId,
                            savedPlaceId: incompleteVisit.savedPlaceId,
                            userId: userId,
                            openTime: incompleteVisit.entryTime,
                            visitCount: sessionVisits.count
                        )
                    }
                }
            }

            // DEBUG: Commented out to reduce console spam
            // print("🔍 ===== SESSION RECOVERY COMPLETE =====\n")
        } catch {
            print("❌ Error recovering sessions: \(error)")
        }
    }

    // MARK: - Stale Session Cleanup

    /// Auto-close sessions that have been open for too long
    private func autoCloseSession(_ sessionId: UUID, userId: UUID) async {
        guard let session = activeSessions[sessionId] else { return }

        // Set exit time for all visits in this session
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let updateData: [String: PostgREST.AnyJSON] = [
                "exit_time": .string(formatter.string(from: Date())),
                "duration_minutes": .double(Double(session.durationMinutes)),
                "updated_at": .string(formatter.string(from: Date()))
            ]

            try await client
                .from("location_visits")
                .update(updateData)
                .eq("session_id", value: sessionId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()

            closeSession(sessionId)
            print("✅ Auto-closed stale session: \(sessionId.uuidString)")
        } catch {
            print("❌ Error auto-closing session: \(error)")
        }
    }

    /// Manual cleanup of all stale sessions
    func cleanupStaleSessions(olderThanHours: Int = 4) async {
        let staleThreshold = TimeInterval(olderThanHours * 3600)
        let now = Date()

        for (sessionId, session) in activeSessions {
            let age = now.timeIntervalSince(session.openTime)
            if age > staleThreshold && session.isOpen {
                print("🧹 Cleaning up stale session: \(sessionId.uuidString) (age: \(Int(age / 3600))h)")
                await autoCloseSession(sessionId, userId: session.userId)
            }
        }
    }

    // MARK: - Session Querying

    /// Query Supabase for all visits in a session
    func getSessionVisits(_ sessionId: UUID, userId: UUID) async -> [LocationVisitRecord]? {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("session_id", value: sessionId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: true)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            return visits.isEmpty ? nil : visits
        } catch {
            print("❌ Error fetching session visits: \(error)")
            return nil
        }
    }

    // MARK: - Debugging & Testing

    /// Get all sessions (active and cached)
    func getAllSessions() -> [SessionInfo] {
        return Array(activeSessions.values)
    }

    /// Clear all cached sessions
    func clearCache() {
        activeSessions.removeAll()
    }

    /// Print session summary
    func printSessionSummary() {
        print("\n📊 ===== SESSION SUMMARY =====")
        print("Active sessions: \(activeSessions.count)")
        for (id, session) in activeSessions {
            print("  - \(id.uuidString)")
            print("    Place: \(session.savedPlaceId.uuidString)")
            print("    Open time: \(session.openTime)")
            print("    Duration: \(session.durationMinutes) min")
            print("    Visits: \(session.visitCount)")
            print("    Status: \(session.isOpen ? "OPEN" : "CLOSED")")
        }
        print("📊 ============================\n")
    }
}
