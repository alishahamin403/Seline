import Foundation
import PostgREST

@MainActor
final class DaySummaryService {
    static let shared = DaySummaryService()

    struct DaySummarySourceRef: Codable, Hashable {
        let type: AgentEntityType
        let id: String
        let title: String?
        let relationType: String
        let label: String?

        var entityRef: EntityRef {
            EntityRef(type: type, id: id, title: title)
        }

        func matches(_ relationTypes: Set<String>) -> Bool {
            guard !relationTypes.isEmpty else { return true }

            let normalizedRelation = relationType.lowercased()
            if relationTypes.contains(normalizedRelation) || relationTypes.contains(type.rawValue.lowercased()) {
                return true
            }

            switch type {
            case .location:
                return relationTypes.contains("place") || relationTypes.contains("location")
            case .event:
                return relationTypes.contains("event") || relationTypes.contains("task")
            default:
                return false
            }
        }
    }

    struct DaySummary: Codable, Hashable, Identifiable {
        let id: UUID
        let summaryDate: Date
        let title: String
        let summaryText: String
        let mood: String?
        let highlights: [String]
        let openLoops: [String]
        let anomalies: [String]
        let sourceRefs: [DaySummarySourceRef]
        let metadata: [String: String]
        let embeddingText: String
        let createdAt: Date?
        let updatedAt: Date?

        var hasMeaningfulEvidence: Bool {
            !sourceRefs.isEmpty ||
            !highlights.isEmpty ||
            !openLoops.isEmpty ||
            !anomalies.isEmpty ||
            !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct DaySummaryRow: Codable {
        let id: UUID
        let summaryDate: String
        let title: String
        let summaryText: String
        let mood: String?
        let highlights: [String]?
        let openLoops: [String]?
        let anomalies: [String]?
        let sourceRefs: [DaySummarySourceRef]?
        let metadata: [String: String]?
        let embeddingText: String?
        let createdAt: Date?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case summaryDate = "summary_date"
            case title
            case summaryText = "summary_text"
            case mood
            case highlights = "highlights_json"
            case openLoops = "open_loops_json"
            case anomalies = "anomalies_json"
            case sourceRefs = "source_refs_json"
            case metadata = "metadata_json"
            case embeddingText = "embedding_text"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    private struct ExtractedDaySummary: Decodable {
        let title: String?
        let summary: String?
        let highlights: [String]
        let openLoops: [String]
        let anomalies: [String]
        let mood: String?

        enum CodingKeys: String, CodingKey {
            case title
            case summary
            case highlights
            case openLoops
            case openLoopsSnake = "open_loops"
            case anomalies
            case mood
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            highlights = try container.decodeIfPresent([String].self, forKey: .highlights) ?? []
            openLoops = try container.decodeIfPresent([String].self, forKey: .openLoops)
                ?? (try container.decodeIfPresent([String].self, forKey: .openLoopsSnake))
                ?? []
            anomalies = try container.decodeIfPresent([String].self, forKey: .anomalies) ?? []
            mood = try container.decodeIfPresent(String.self, forKey: .mood)
        }
    }

    private struct DaySnapshot {
        let date: Date
        let journalEntry: Note?
        let weeklyRecap: Note?
        let tasks: [TaskItem]
        let completedTasks: [TaskItem]
        let incompleteTasks: [TaskItem]
        let visits: [LocationVisitRecord]
        let peopleByVisit: [UUID: [Person]]
        let receipts: [ReceiptStat]
        let inboxEmails: [Email]
        let sentEmails: [Email]
        let visitAnomalies: [String]
    }

    private struct FallbackSummaryComponents {
        let title: String
        let summary: String
        let mood: String?
        let highlights: [String]
        let openLoops: [String]
        let anomalies: [String]
    }

    private let notesManager = NotesManager.shared
    private let taskManager = TaskManager.shared
    private let emailService = EmailService.shared
    private let peopleManager = PeopleManager.shared
    private let locationsManager = LocationsManager.shared
    private let geminiService = GeminiService.shared
    private let outlierDetectionService = OutlierDetectionService.shared

    private let refreshIntervalForToday: TimeInterval = 20 * 60
    private let refreshIntervalForRecentDays: TimeInterval = 6 * 60 * 60

    private init() {}

    func summary(for date: Date, forceRefresh: Bool = false) async -> DaySummary? {
        let normalizedDate = normalizedDay(date)
        let storedSummary = await fetchSummary(for: normalizedDate)

        if !forceRefresh,
           let storedSummary,
           !shouldRefresh(storedSummary, for: normalizedDate) {
            return storedSummary
        }

        let builtSummary = await buildSummary(for: normalizedDate, existing: storedSummary)
        guard let builtSummary else {
            return storedSummary
        }

        if let persistedSummary = await upsert(summary: builtSummary) {
            return persistedSummary
        }

        return builtSummary
    }

    func refreshSummary(for date: Date) async -> DaySummary? {
        await summary(for: date, forceRefresh: true)
    }

    func summary(id: UUID) async -> DaySummary? {
        await fetchSummary(id: id)
    }

    func relatedEntityRefs(for summaryId: UUID, relationTypes: Set<String> = []) async -> [EntityRef] {
        guard let summary = await fetchSummary(id: summaryId) else { return [] }
        return summary.sourceRefs
            .filter { $0.matches(relationTypes) }
            .map(\.entityRef)
    }

    func refreshSummariesAffected(by note: Note) async {
        let affectedDates = datesAffected(by: note)
        guard !affectedDates.isEmpty else { return }

        for date in affectedDates {
            _ = await refreshSummary(for: date)
        }
    }

    private func shouldRefresh(_ summary: DaySummary, for date: Date) -> Bool {
        guard let updatedAt = summary.updatedAt else { return true }

        let age = Date().timeIntervalSince(updatedAt)
        if Calendar.current.isDateInToday(date) {
            return age > refreshIntervalForToday
        }

        if Date().timeIntervalSince(date) < (7 * 24 * 60 * 60) {
            return age > refreshIntervalForRecentDays
        }

        return false
    }

    private func buildSummary(for date: Date, existing: DaySummary?) async -> DaySummary? {
        let snapshot = await collectSnapshot(for: date)
        let fallback = fallbackSummaryComponents(from: snapshot)
        let extracted = await llmSummary(for: snapshot)

        let title = normalizedLine(extracted?.title) ?? fallback.title
        let summaryText = normalizedLine(extracted?.summary) ?? fallback.summary
        let mood = normalizedLine(extracted?.mood) ?? fallback.mood
        let highlights = normalizedLines(extracted?.highlights ?? fallback.highlights, maxCount: 4)
        let openLoops = normalizedLines(extracted?.openLoops ?? fallback.openLoops, maxCount: 4)
        let anomalies = normalizedLines(extracted?.anomalies ?? fallback.anomalies, maxCount: 4)
        let sourceRefs = sourceRefs(for: snapshot)
        let metadata = metadata(for: snapshot, mood: mood)
        let embeddingText = embeddingText(
            date: date,
            title: title,
            summaryText: summaryText,
            mood: mood,
            highlights: highlights,
            openLoops: openLoops,
            anomalies: anomalies,
            sourceRefs: sourceRefs
        )

        return DaySummary(
            id: existing?.id ?? UUID(),
            summaryDate: date,
            title: title,
            summaryText: summaryText,
            mood: mood,
            highlights: highlights,
            openLoops: openLoops,
            anomalies: anomalies,
            sourceRefs: sourceRefs,
            metadata: metadata,
            embeddingText: embeddingText,
            createdAt: existing?.createdAt,
            updatedAt: Date()
        )
    }

    private func collectSnapshot(for date: Date) async -> DaySnapshot {
        let journalEntry = notesManager.meaningfulJournalEntry(for: date) ?? notesManager.journalEntry(for: date)
        let weeklyRecap = weeklyRecap(containing: date)
        let tasks = taskManager.getAllTasks(for: date)
        let completedTasks = tasks.filter { $0.isCompletedOn(date: date) }
        let incompleteTasks = tasks.filter { !$0.isCompletedOn(date: date) }
        let visits = await fetchVisits(for: date)
        let peopleByVisit = await peopleManager.getPeopleForVisits(visitIds: visits.map(\.id))
        let receipts = await receipts(for: date)
        let inboxEmails = emailsForDay(emailService.inboxEmails, on: date)
        let sentEmails = emailsForDay(emailService.sentEmails, on: date)
        let visitAnomalies = await detectVisitAnomalies(for: visits)

        return DaySnapshot(
            date: date,
            journalEntry: journalEntry,
            weeklyRecap: weeklyRecap,
            tasks: tasks,
            completedTasks: completedTasks,
            incompleteTasks: incompleteTasks,
            visits: visits,
            peopleByVisit: peopleByVisit,
            receipts: receipts,
            inboxEmails: inboxEmails,
            sentEmails: sentEmails,
            visitAnomalies: visitAnomalies
        )
    }

    private func fallbackSummaryComponents(from snapshot: DaySnapshot) -> FallbackSummaryComponents {
        let dateLabel = longDateString(snapshot.date)
        let uniquePlaceNames = snapshot.visits.compactMap { placeName(for: $0.savedPlaceId) }
        let uniquePeople = Array(
            Set(snapshot.peopleByVisit.values.flatMap { $0.map(\.displayName) })
        ).sorted()
        let totalSpend = snapshot.receipts.reduce(0) { $0 + $1.amount }
        let actionEmails = prioritizedEmails(from: snapshot).filter { !$0.isRead || $0.requiresAction }
        let mood = snapshot.journalEntry?.journalMood?.title

        var summaryParts: [String] = []
        if let mood {
            summaryParts.append("Your journal mood for \(dateLabel) was \(mood.lowercased()).")
        }

        if let journalEntry = snapshot.journalEntry {
            let journalPreview = clippedSentence(journalEntry.displayContent, limit: 180)
            if !journalPreview.isEmpty {
                summaryParts.append("Journal notes mention \(journalPreview)")
            }
        }

        if !snapshot.tasks.isEmpty {
            summaryParts.append("You had \(snapshot.tasks.count) scheduled item\(snapshot.tasks.count == 1 ? "" : "s"), with \(snapshot.completedTasks.count) marked complete and \(snapshot.incompleteTasks.count) still open.")
        }

        if !snapshot.visits.isEmpty {
            let placeSummary = Array(Set(uniquePlaceNames)).prefix(3).joined(separator: ", ")
            let peopleSummary = uniquePeople.prefix(3).joined(separator: ", ")
            var visitSentence = "You logged \(snapshot.visits.count) visit\(snapshot.visits.count == 1 ? "" : "s")"
            if !placeSummary.isEmpty {
                visitSentence += " including \(placeSummary)"
            }
            visitSentence += "."
            summaryParts.append(visitSentence)

            if !peopleSummary.isEmpty {
                summaryParts.append("People linked to that day include \(peopleSummary).")
            }
        }

        if !snapshot.receipts.isEmpty {
            summaryParts.append("Spending totaled \(CurrencyParser.formatAmount(totalSpend)) across \(snapshot.receipts.count) receipt\(snapshot.receipts.count == 1 ? "" : "s").")
        }

        if !actionEmails.isEmpty {
            summaryParts.append("There were \(actionEmails.count) email\(actionEmails.count == 1 ? "" : "s") that looked unread or action-oriented.")
        }

        if summaryParts.isEmpty {
            summaryParts.append("I found very little Seline activity for \(dateLabel).")
        }

        var highlights: [String] = []
        if let mood {
            highlights.append("Journal mood: \(mood)")
        }
        if let journalEntry = snapshot.journalEntry {
            let preview = clippedSentence(journalEntry.displayContent, limit: 120)
            if !preview.isEmpty {
                highlights.append("Journal: \(preview)")
            }
        }
        if !snapshot.completedTasks.isEmpty {
            let taskTitles = snapshot.completedTasks.prefix(3).map(\.title).joined(separator: ", ")
            highlights.append("Completed: \(taskTitles)")
        }
        if !snapshot.visits.isEmpty {
            let visitTitles = Array(Set(uniquePlaceNames)).prefix(3).joined(separator: ", ")
            if !visitTitles.isEmpty {
                highlights.append("Visited: \(visitTitles)")
            }
        }
        if totalSpend > 0 {
            highlights.append("Spent \(CurrencyParser.formatAmount(totalSpend))")
        }
        if !uniquePeople.isEmpty {
            highlights.append("People: \(uniquePeople.prefix(3).joined(separator: ", "))")
        }

        var openLoops: [String] = []
        if !snapshot.incompleteTasks.isEmpty {
            let taskTitles = snapshot.incompleteTasks.prefix(3).map(\.title).joined(separator: ", ")
            openLoops.append("Still open: \(taskTitles)")
        }
        if !actionEmails.isEmpty {
            let subjects = actionEmails.prefix(2).map(\.subject).joined(separator: ", ")
            openLoops.append("Emails to review: \(subjects)")
        }

        return FallbackSummaryComponents(
            title: "Day context for \(shortDateString(snapshot.date))",
            summary: summaryParts.joined(separator: " "),
            mood: mood,
            highlights: highlights,
            openLoops: openLoops,
            anomalies: snapshot.visitAnomalies
        )
    }

    private func llmSummary(for snapshot: DaySnapshot) async -> ExtractedDaySummary? {
        let evidenceText = llmEvidenceText(for: snapshot)
        let systemPrompt = """
        You summarize a single day of personal app data for Seline.

        Rules:
        - Use only the supplied evidence.
        - Personalize the writing, but never invent facts.
        - Mention unusual patterns only when the evidence explicitly supports them.
        - Keep the summary compact and useful for a chat assistant.
        - Return strict JSON only.
        """

        let userPrompt = """
        Create a compact day-context JSON object with this exact schema:
        {
          "title": "short title",
          "summary": "2-4 sentences",
          "mood": "optional short mood label or empty string",
          "highlights": ["short bullet", "short bullet"],
          "open_loops": ["short bullet"],
          "anomalies": ["short bullet"]
        }

        Constraints:
        - `highlights`, `open_loops`, and `anomalies` should each have at most 4 items.
        - If a section has nothing useful, return an empty array.
        - If there is no reliable mood evidence, use an empty string.
        - Prefer concrete details across journal, schedule, visits, spending, people, and email.

        Day evidence:
        \(evidenceText)
        """

        do {
            let response = try await geminiService.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: 700,
                temperature: 0.1,
                operationType: "day_summary"
            )
            return parseExtractedSummary(from: response)
        } catch {
            print("⚠️ Failed to generate LLM day summary: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseExtractedSummary(from raw: String) -> ExtractedDaySummary? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }

        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            return try JSONDecoder().decode(ExtractedDaySummary.self, from: data)
        } catch {
            print("⚠️ Failed to parse day summary JSON: \(error.localizedDescription)")
            return nil
        }
    }

    private func llmEvidenceText(for snapshot: DaySnapshot) -> String {
        var lines: [String] = [
            "Date: \(longDateString(snapshot.date))"
        ]

        if let journalEntry = snapshot.journalEntry {
            lines.append("Journal title: \(journalEntry.title)")
            if let mood = journalEntry.journalMood?.title {
                lines.append("Journal mood: \(mood)")
            }
            let content = journalEntry.displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                lines.append("Journal text: \(String(content.prefix(900)))")
            }
        } else {
            lines.append("Journal: none")
        }

        if let weeklyRecap = snapshot.weeklyRecap {
            lines.append("Weekly recap context: \(String(weeklyRecap.displayContent.prefix(500)))")
        }

        if snapshot.tasks.isEmpty {
            lines.append("Tasks: none")
        } else {
            lines.append("Tasks:")
            for task in snapshot.tasks.prefix(8) {
                let status = task.isCompletedOn(date: snapshot.date) ? "done" : "open"
                let time = task.formattedTimeRange.nilIfEmpty ?? task.formattedTime.nilIfEmpty ?? "no time"
                lines.append("- [\(status)] \(task.title) (\(time))")
            }
        }

        if snapshot.visits.isEmpty {
            lines.append("Visits: none")
        } else {
            lines.append("Visits:")
            for visit in snapshot.visits.prefix(8) {
                let people = snapshot.peopleByVisit[visit.id, default: []]
                    .map(\.displayName)
                    .prefix(3)
                    .joined(separator: ", ")
                let peopleSuffix = people.isEmpty ? "" : " | people: \(people)"
                let durationSuffix = visit.durationMinutes.map { " | duration: \($0)m" } ?? ""
                lines.append("- \(placeName(for: visit.savedPlaceId)) | entry: \(localTimeString(visit.entryTime))\(durationSuffix)\(peopleSuffix)")
            }
        }

        if snapshot.receipts.isEmpty {
            lines.append("Receipts: none")
        } else {
            let total = snapshot.receipts.reduce(0) { $0 + $1.amount }
            lines.append("Receipts total: \(CurrencyParser.formatAmount(total))")
            for receipt in snapshot.receipts.prefix(6) {
                lines.append("- \(receipt.title) | \(CurrencyParser.formatAmount(receipt.amount)) | \(receipt.category)")
            }
        }

        let allEmails = prioritizedEmails(from: snapshot)
        if allEmails.isEmpty {
            lines.append("Emails: none")
        } else {
            lines.append("Emails:")
            for email in allEmails.prefix(6) {
                let flags = [
                    !email.isRead ? "unread" : nil,
                    email.requiresAction ? "action" : nil
                ].compactMap { $0 }.joined(separator: ", ")
                let flagText = flags.isEmpty ? "" : " | \(flags)"
                lines.append("- \(email.subject) | from \(email.sender.name)\(flagText)")
            }
        }

        if snapshot.visitAnomalies.isEmpty {
            lines.append("Potential anomalies: none")
        } else {
            lines.append("Potential anomalies:")
            snapshot.visitAnomalies.prefix(4).forEach { lines.append("- \($0)") }
        }

        return lines.joined(separator: "\n")
    }

    private func sourceRefs(for snapshot: DaySnapshot) -> [DaySummarySourceRef] {
        var refs: [DaySummarySourceRef] = []
        var seen = Set<String>()

        func append(
            type: AgentEntityType,
            id: String,
            title: String?,
            relationType: String,
            label: String?
        ) {
            let key = "\(type.rawValue):\(id)"
            guard seen.insert(key).inserted else { return }
            refs.append(
                DaySummarySourceRef(
                    type: type,
                    id: id,
                    title: title,
                    relationType: relationType,
                    label: label
                )
            )
        }

        if let journalEntry = snapshot.journalEntry {
            append(type: .note, id: journalEntry.id.uuidString, title: journalEntry.title, relationType: "journal", label: "Journal entry")
        }
        if let weeklyRecap = snapshot.weeklyRecap {
            append(type: .note, id: weeklyRecap.id.uuidString, title: weeklyRecap.title, relationType: "weekly_recap", label: "Weekly recap")
        }

        for task in snapshot.tasks.prefix(6) {
            append(type: .event, id: task.id, title: task.title, relationType: "event", label: "Scheduled item")
        }

        for visit in snapshot.visits.prefix(6) {
            append(type: .visit, id: visit.id.uuidString, title: placeName(for: visit.savedPlaceId), relationType: "visit", label: "Visit")
        }

        let uniquePlaceIds = Array(Set(snapshot.visits.map(\.savedPlaceId)))
        for placeId in uniquePlaceIds.prefix(4) {
            let title = placeName(for: placeId)
            append(type: .location, id: placeId.uuidString, title: title, relationType: "place", label: "Visited place")
        }

        let uniquePeople = Array(
            Set(snapshot.peopleByVisit.values.flatMap { $0 })
        ).sorted { $0.displayName < $1.displayName }
        for person in uniquePeople.prefix(4) {
            append(type: .person, id: person.id.uuidString, title: person.displayName, relationType: "person", label: "Person")
        }

        for receipt in snapshot.receipts.prefix(6) {
            append(type: .receipt, id: receipt.noteId.uuidString, title: receipt.title, relationType: "receipt", label: "Receipt")
        }

        for email in prioritizedEmails(from: snapshot).prefix(4) {
            append(type: .email, id: email.id, title: email.subject, relationType: "email", label: "Email")
        }

        return refs
    }

    private func metadata(for snapshot: DaySnapshot, mood: String?) -> [String: String] {
        let uniquePeopleCount = Set(snapshot.peopleByVisit.values.flatMap { $0.map(\.id) }).count
        let uniquePlaceCount = Set(snapshot.visits.map(\.savedPlaceId)).count

        var metadata: [String: String] = [
            "task_count": "\(snapshot.tasks.count)",
            "completed_task_count": "\(snapshot.completedTasks.count)",
            "open_task_count": "\(snapshot.incompleteTasks.count)",
            "visit_count": "\(snapshot.visits.count)",
            "receipt_count": "\(snapshot.receipts.count)",
            "email_count": "\(snapshot.inboxEmails.count + snapshot.sentEmails.count)",
            "person_count": "\(uniquePeopleCount)",
            "place_count": "\(uniquePlaceCount)"
        ]

        if let mood {
            metadata["mood"] = mood
        }

        return metadata
    }

    private func embeddingText(
        date: Date,
        title: String,
        summaryText: String,
        mood: String?,
        highlights: [String],
        openLoops: [String],
        anomalies: [String],
        sourceRefs: [DaySummarySourceRef]
    ) -> String {
        var lines: [String] = [
            "Day Summary",
            "Date: \(longDateString(date))",
            "Title: \(title)",
            "Summary: \(summaryText)"
        ]

        if let mood, !mood.isEmpty {
            lines.append("Mood: \(mood)")
        }

        if !highlights.isEmpty {
            lines.append("Highlights:")
            highlights.forEach { lines.append("- \($0)") }
        }

        if !openLoops.isEmpty {
            lines.append("Open loops:")
            openLoops.forEach { lines.append("- \($0)") }
        }

        if !anomalies.isEmpty {
            lines.append("Anomalies:")
            anomalies.forEach { lines.append("- \($0)") }
        }

        if !sourceRefs.isEmpty {
            lines.append("Source records:")
            sourceRefs.prefix(10).forEach { source in
                let title = source.title?.nilIfEmpty ?? source.id
                lines.append("- \(source.relationType): \(title)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func fetchSummary(for date: Date) async -> DaySummary? {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return nil }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("day_summaries")
                .select()
                .eq("summary_date", value: storageDayString(for: date))
                .limit(1)
                .execute()

            let rows = try JSONDecoder.supabaseDecoder().decode([DaySummaryRow].self, from: response.data)
            return rows.first.flatMap { daySummary(from: $0) }
        } catch {
            print("⚠️ Failed to fetch day summary for \(storageDayString(for: date)): \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSummary(id: UUID) async -> DaySummary? {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return nil }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("day_summaries")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()

            let rows = try JSONDecoder.supabaseDecoder().decode([DaySummaryRow].self, from: response.data)
            return rows.first.flatMap { daySummary(from: $0) }
        } catch {
            print("⚠️ Failed to fetch day summary \(id.uuidString): \(error.localizedDescription)")
            return nil
        }
    }

    private func upsert(summary: DaySummary) async -> DaySummary? {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return summary
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let payload = try payload(for: summary, userId: userId)
            try await client
                .from("day_summaries")
                .upsert(payload, onConflict: "user_id,summary_date")
                .execute()

            return await fetchSummary(for: summary.summaryDate) ?? summary
        } catch {
            print("⚠️ Failed to upsert day summary for \(storageDayString(for: summary.summaryDate)): \(error.localizedDescription)")
            return summary
        }
    }

    private func payload(for summary: DaySummary, userId: UUID) throws -> [String: PostgREST.AnyJSON] {
        let sourceRefPayload: [[String: Any]] = summary.sourceRefs.map { source in
            [
                "type": source.type.rawValue,
                "id": source.id,
                "title": source.title ?? "",
                "relation_type": source.relationType,
                "label": source.label ?? ""
            ]
        }
        let metadataPayload: [String: Any] = summary.metadata.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value
        }

        var payload: [String: PostgREST.AnyJSON] = [
            "id": .string(summary.id.uuidString),
            "user_id": .string(userId.uuidString),
            "summary_date": .string(storageDayString(for: summary.summaryDate)),
            "title": .string(summary.title),
            "summary_text": .string(summary.summaryText),
            "highlights_json": try convertToAnyJSON(summary.highlights),
            "open_loops_json": try convertToAnyJSON(summary.openLoops),
            "anomalies_json": try convertToAnyJSON(summary.anomalies),
            "source_refs_json": try convertToAnyJSON(sourceRefPayload),
            "metadata_json": try convertToAnyJSON(metadataPayload),
            "embedding_text": .string(summary.embeddingText),
            "updated_at": .string(ISO8601DateFormatter().string(from: summary.updatedAt ?? Date()))
        ]

        if let mood = summary.mood, !mood.isEmpty {
            payload["mood"] = .string(mood)
        } else {
            payload["mood"] = .null
        }

        if let createdAt = summary.createdAt {
            payload["created_at"] = .string(ISO8601DateFormatter().string(from: createdAt))
        }

        return payload
    }

    private func daySummary(from row: DaySummaryRow) -> DaySummary? {
        guard let summaryDate = parsedStorageDay(row.summaryDate) else { return nil }

        return DaySummary(
            id: row.id,
            summaryDate: summaryDate,
            title: row.title,
            summaryText: row.summaryText,
            mood: normalizedLine(row.mood),
            highlights: normalizedLines(row.highlights ?? [], maxCount: 6),
            openLoops: normalizedLines(row.openLoops ?? [], maxCount: 6),
            anomalies: normalizedLines(row.anomalies ?? [], maxCount: 6),
            sourceRefs: row.sourceRefs ?? [],
            metadata: row.metadata ?? [:],
            embeddingText: row.embeddingText ?? "",
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }

    private func fetchVisits(for date: Date) async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let interval = dayInterval(for: date)
            let iso = ISO8601DateFormatter()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: iso.string(from: interval.start))
                .lt("entry_time", value: iso.string(from: interval.end))
                .order("entry_time", ascending: true)
                .execute()

            return try JSONDecoder.supabaseDecoder().decode([LocationVisitRecord].self, from: response.data)
        } catch {
            print("⚠️ Failed to fetch visits for day summary: \(error.localizedDescription)")
            return []
        }
    }

    private func receipts(for date: Date) async -> [ReceiptStat] {
        await notesManager.ensureReceiptDataAvailable()
        let calendar = Calendar.current
        return notesManager
            .getReceiptStatistics()
            .flatMap(\.monthlySummaries)
            .flatMap(\.receipts)
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    private func detectVisitAnomalies(for visits: [LocationVisitRecord]) async -> [String] {
        guard !visits.isEmpty else { return [] }

        var anomalies: [String] = []
        for visit in visits.prefix(5) {
            if visit.isOutlier == true {
                anomalies.append("Visit to \(placeName(for: visit.savedPlaceId)) was already flagged as unusual.")
                continue
            }

            guard let duration = visit.durationMinutes, duration >= 10 else { continue }
            let analysis = await outlierDetectionService.detectOutlier(
                placeId: visit.savedPlaceId,
                duration: duration,
                entryTime: visit.entryTime
            )

            if analysis.isOutlier || (analysis.reason == "duration_unusual" && analysis.confidence >= 0.7) {
                let direction = duration >= Int(analysis.statistics?.mean ?? Double(duration))
                    ? "longer"
                    : "shorter"
                anomalies.append("Visit to \(placeName(for: visit.savedPlaceId)) was \(direction) than usual at \(duration) minutes.")
            }
        }

        return Array(anomalies.prefix(4))
    }

    private func datesAffected(by note: Note) -> [Date] {
        let calendar = Calendar.current

        if note.isJournalEntry, let journalDate = note.journalDate {
            return [calendar.startOfDay(for: journalDate)]
        }

        if note.isJournalWeeklyRecap, let weekStart = note.journalWeekStartDate {
            return (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart))
            }
        }

        return []
    }

    private func weeklyRecap(containing date: Date) -> Note? {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        return notesManager.journalWeeklyRecaps.first { recap in
            guard let weekStart = recap.journalWeekStartDate else { return false }
            let normalizedStart = calendar.startOfDay(for: weekStart)
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: normalizedStart) else {
                return false
            }
            return targetDate >= normalizedStart && targetDate <= weekEnd
        }
    }

    private func prioritizedEmails(from snapshot: DaySnapshot) -> [Email] {
        let combined = snapshot.inboxEmails + snapshot.sentEmails
        return combined.sorted { lhs, rhs in
            let lhsScore = (lhs.requiresAction ? 2 : 0) + (!lhs.isRead ? 1 : 0)
            let rhsScore = (rhs.requiresAction ? 2 : 0) + (!rhs.isRead ? 1 : 0)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    private func emailsForDay(_ emails: [Email], on date: Date) -> [Email] {
        let calendar = Calendar.current
        return emails
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func placeName(for placeId: UUID) -> String {
        locationsManager.savedPlaces.first(where: { $0.id == placeId })?.displayName ?? "Place"
    }

    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func dayInterval(for date: Date) -> DateInterval {
        let start = normalizedDay(date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func storageDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: normalizedDay(date))
    }

    private func parsedStorageDay(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func longDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func localTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func clippedSentence(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedLines(_ values: [String], maxCount: Int) -> [String] {
        Array(
            values
                .compactMap { normalizedLine($0) }
                .prefix(maxCount)
        )
    }

    private func convertToAnyJSON(_ object: Any) throws -> PostgREST.AnyJSON {
        if let dict = object as? [String: Any] {
            var result: [String: PostgREST.AnyJSON] = [:]
            for (key, value) in dict {
                result[key] = try convertToAnyJSON(value)
            }
            return .object(result)
        } else if let array = object as? [Any] {
            return .array(try array.map { try convertToAnyJSON($0) })
        } else if let string = object as? String {
            return .string(string)
        } else if let bool = object as? Bool {
            return .bool(bool)
        } else if let number = object as? NSNumber {
            if CFNumberGetType(number as CFNumber) == .charType {
                return .bool(number.boolValue)
            }
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return .integer(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        } else if object is NSNull {
            return .null
        }

        throw NSError(
            domain: "DaySummaryService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON type: \(type(of: object))"]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
