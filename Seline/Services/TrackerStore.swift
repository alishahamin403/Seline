import Foundation
import PostgREST

@MainActor
final class TrackerStore: ObservableObject {
    static let shared = TrackerStore()

    @Published private(set) var threads: [TrackerThread] = []
    @Published private(set) var syncState: TrackerSyncState = .idle

    private let threadsStorageKey = "trackerThreads.v2"
    private let lastActiveThreadKey = "trackerLastActiveThreadID.v2"
    private let deletedThreadIDsStorageKey = "trackerDeletedThreadIDs.v1"
    private let isoFormatter = ISO8601DateFormatter()
    private let engine = TrackerEngine.shared
    private let parserService = TrackerParserService.shared
    private var deletedThreadIDs = Set<UUID>()

    private init() {
        loadDeletedThreadIDs()
        loadLocalThreads()
    }

    func loadLocalThreads() {
        guard let data = UserDefaults.standard.data(forKey: threadsStorageKey) else {
            threads = []
            return
        }

        do {
            let decodedThreads = try JSONDecoder().decode([TrackerThread].self, from: data)
            let normalizedThreads = decodedThreads.map(parserService.normalizedThread)
                .sorted { $0.updatedAt > $1.updatedAt }
            threads = normalizedThreads
            if normalizedThreads != decodedThreads.sorted(by: { $0.updatedAt > $1.updatedAt }) {
                saveLocalThreads()
            }
        } catch {
            print("❌ Failed to decode tracker threads: \(error)")
            threads = []
        }
    }

    func saveLocalThreads() {
        do {
            let data = try JSONEncoder().encode(threads.sorted { $0.updatedAt > $1.updatedAt })
            UserDefaults.standard.set(data, forKey: threadsStorageKey)
        } catch {
            print("❌ Failed to save tracker threads: \(error)")
        }
    }

    func thread(id: UUID?) -> TrackerThread? {
        guard let id else { return nil }
        return threads.first(where: { $0.id == id })
    }

    func upsertThread(_ thread: TrackerThread) {
        let normalizedThread = parserService.normalizedThread(thread)
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = normalizedThread
        } else {
            threads.insert(normalizedThread, at: 0)
        }
        threads.sort { $0.updatedAt > $1.updatedAt }
        saveLocalThreads()
        setLastActiveThreadID(normalizedThread.id)
    }

    func deleteThread(id: UUID) {
        threads.removeAll { $0.id == id }
        deletedThreadIDs.insert(id)
        if lastActiveThreadID() == id {
            UserDefaults.standard.removeObject(forKey: lastActiveThreadKey)
        }
        saveLocalThreads()
        saveDeletedThreadIDs()

        Task {
            await deleteThreadFromSupabase(id: id)
        }
    }

    func clearLocalData() {
        threads = []
        UserDefaults.standard.removeObject(forKey: threadsStorageKey)
        UserDefaults.standard.removeObject(forKey: lastActiveThreadKey)
        UserDefaults.standard.removeObject(forKey: deletedThreadIDsStorageKey)
        deletedThreadIDs = []
        syncState = .idle
    }

    func setLastActiveThreadID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: lastActiveThreadKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastActiveThreadKey)
        }
    }

    func lastActiveThreadID() -> UUID? {
        guard let value = UserDefaults.standard.string(forKey: lastActiveThreadKey) else { return nil }
        return UUID(uuidString: value)
    }

    func syncThread(
        _ thread: TrackerThread,
        messages: [ConversationMessage]
    ) async {
        let normalizedThread = parserService.normalizedThread(thread)
        guard !deletedThreadIDs.contains(thread.id) else { return }
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }
        syncState = .syncing

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let memoryData = try JSONEncoder().encode(normalizedThread.memorySnapshot)
            let memoryJSONString = String(decoding: memoryData, as: UTF8.self)
            let summary = normalizedThread.cachedState?.summaryLine
                ?? normalizedThread.subtitle
                ?? normalizedThread.memorySnapshot.normalizedSummaryText
            let trackerMessages = messages.filter { $0.trackerThreadId == normalizedThread.id }
            let latestMessageTimestamp = trackerMessages.map(\.timestamp).max()
            let remoteUpdatedAt = max(normalizedThread.updatedAt, latestMessageTimestamp ?? normalizedThread.updatedAt)

            let threadRow: [String: AnyJSON] = [
                "id": .string(normalizedThread.id.uuidString),
                "user_id": .string(userId.uuidString),
                "title": .string(normalizedThread.title),
                "status": .string(normalizedThread.status.rawValue),
                "rule_json": .string(memoryJSONString),
                "summary_text": summary.trackerNonEmpty.map(AnyJSON.string) ?? .null,
                "subtitle": normalizedThread.subtitle.flatMap { $0.trackerNonEmpty }.map(AnyJSON.string) ?? .null,
                "updated_at": .string(isoFormatter.string(from: remoteUpdatedAt)),
                "created_at": .string(isoFormatter.string(from: normalizedThread.createdAt))
            ]

            try await client
                .from("tracker_threads")
                .upsert(threadRow, onConflict: "id")
                .execute()

            let messageRows: [[String: AnyJSON]] = trackerMessages.map { message in
                let draftJSON: String? = {
                    guard let draft = message.trackerOperationDraft,
                          let data = try? JSONEncoder().encode(draft) else { return nil }
                    return String(decoding: data, as: UTF8.self)
                }()
                let stateJSON: String? = {
                    guard let snapshot = message.trackerStateSnapshot,
                          let data = try? JSONEncoder().encode(snapshot) else { return nil }
                    return String(decoding: data, as: UTF8.self)
                }()
                return [
                    "id": .string(message.id.uuidString),
                    "tracker_thread_id": .string(normalizedThread.id.uuidString),
                    "user_id": .string(userId.uuidString),
                    "is_user": .bool(message.isUser),
                    "text": .string(message.text),
                    "draft_json": draftJSON.map(AnyJSON.string) ?? .null,
                    "state_json": stateJSON.map(AnyJSON.string) ?? .null,
                    "created_at": .string(isoFormatter.string(from: message.timestamp))
                ]
            }

            if !messageRows.isEmpty {
                try await client
                    .from("tracker_messages")
                    .upsert(messageRows, onConflict: "id")
                    .execute()
            }

            if normalizedThread != thread {
                upsertThread(normalizedThread)
            }

            syncState = .idle
        } catch {
            syncState = .failed
            print("❌ Failed syncing tracker thread: \(error)")
        }
    }

    func refreshFromSupabase() async -> [TrackerRemoteBundle] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }
        syncState = .syncing

        do {
            if !deletedThreadIDs.isEmpty {
                for deletedID in Array(deletedThreadIDs) {
                    await deleteThreadFromSupabase(id: deletedID)
                }
            }

            let client = await SupabaseManager.shared.getPostgrestClient()
            let threadResponse = try await client
                .from("tracker_threads")
                .select("id,title,status,rule_json,summary_text,subtitle,updated_at,created_at")
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .execute()

            let threadRecords = try JSONDecoder.supabaseDecoder().decode([TrackerRemoteThreadRecord].self, from: threadResponse.data)
                .filter { !deletedThreadIDs.contains($0.id) }
            let threadIds = threadRecords.map(\.id)

            var messagesByThread: [UUID: [ConversationMessage]] = [:]

            if !threadIds.isEmpty {
                let messageResponse = try await client
                    .from("tracker_messages")
                    .select("id,tracker_thread_id,is_user,text,draft_json,state_json,created_at")
                    .eq("user_id", value: userId.uuidString)
                    .in("tracker_thread_id", values: threadIds.map(\.uuidString))
                    .order("created_at", ascending: true)
                    .execute()
                let messageRecords = try JSONDecoder.supabaseDecoder().decode([TrackerRemoteMessageRecord].self, from: messageResponse.data)
                messagesByThread = Dictionary(grouping: messageRecords) { $0.tracker_thread_id }
                    .mapValues { records in
                        records.compactMap { record in
                            let draft = decodeDraft(from: record.draft_json)
                            let stateSnapshot = decodeState(from: record.state_json)
                            return ConversationMessage(
                                id: record.id,
                                isUser: record.is_user,
                                text: record.text,
                                timestamp: isoFormatter.date(from: record.created_at) ?? Date(),
                                intent: .general,
                                trackerThreadId: record.tracker_thread_id,
                                trackerOperationDraft: draft,
                                trackerStateSnapshot: stateSnapshot
                            )
                        }
                    }
            }

            let bundles: [TrackerRemoteBundle] = threadRecords.compactMap { record in
                guard let memoryData = record.rule_json.data(using: .utf8),
                      var memorySnapshot = try? JSONDecoder().decode(TrackerMemorySnapshot.self, from: memoryData) else {
                    return nil
                }

                if memorySnapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    memorySnapshot.title = record.title
                }
                if memorySnapshot.currentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let remoteSummary = record.summary_text?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !remoteSummary.isEmpty {
                    memorySnapshot.currentSummary = remoteSummary
                }

                var thread = TrackerThread(
                    id: record.id,
                    title: record.title,
                    status: TrackerThreadStatus(rawValue: record.status) ?? .active,
                    memorySnapshot: memorySnapshot,
                    createdAt: isoFormatter.date(from: record.created_at) ?? Date(),
                    updatedAt: isoFormatter.date(from: record.updated_at) ?? Date(),
                    subtitle: record.subtitle ?? record.summary_text
                )
                thread.cachedState = engine.deriveState(for: thread)
                if thread.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    thread.subtitle = thread.cachedState?.summaryLine
                }
                let normalizedThread = parserService.normalizedThread(thread)
                return TrackerRemoteBundle(thread: normalizedThread, messages: messagesByThread[record.id] ?? [])
            }

            for bundle in bundles {
                if let existing = thread(id: bundle.thread.id),
                   existing.updatedAt > bundle.thread.updatedAt {
                    continue
                }
                upsertThread(bundle.thread)
            }

            syncState = .idle
            return bundles
        } catch {
            syncState = .failed
            print("❌ Failed to refresh tracker threads: \(error)")
            return []
        }
    }

    private func decodeDraft(from raw: String?) -> TrackerOperationDraft? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TrackerOperationDraft.self, from: data)
    }

    private func decodeState(from raw: String?) -> TrackerDerivedState? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TrackerDerivedState.self, from: data)
    }

    private func loadDeletedThreadIDs() {
        let storedIDs = UserDefaults.standard.array(forKey: deletedThreadIDsStorageKey) as? [String] ?? []
        deletedThreadIDs = Set(storedIDs.compactMap(UUID.init(uuidString:)))
    }

    private func saveDeletedThreadIDs() {
        let encodedIDs = deletedThreadIDs.map(\.uuidString)
        UserDefaults.standard.set(encodedIDs, forKey: deletedThreadIDsStorageKey)
    }

    private func deleteThreadFromSupabase(id: UUID) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("tracker_threads")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("id", value: id.uuidString)
                .execute()

            if deletedThreadIDs.remove(id) != nil {
                saveDeletedThreadIDs()
            }
        } catch {
            print("❌ Failed deleting tracker thread from Supabase: \(error)")
        }
    }
}

struct TrackerRemoteBundle {
    var thread: TrackerThread
    var messages: [ConversationMessage]
}
