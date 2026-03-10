import Foundation

@MainActor
final class JournalService: ObservableObject {
    static let shared = JournalService()

    @Published var isPromptEnabled: Bool {
        didSet {
            userDefaults.set(isPromptEnabled, forKey: Self.promptEnabledKey)
            Task {
                if isPromptEnabled {
                    await scheduleDailyPromptIfNeeded()
                } else {
                    cancelDailyPrompt()
                }
            }
        }
    }

    @Published var promptHour: Int {
        didSet {
            userDefaults.set(promptHour, forKey: Self.promptHourKey)
            Task {
                if isPromptEnabled {
                    await scheduleDailyPromptIfNeeded()
                }
            }
        }
    }

    @Published var promptMinute: Int {
        didSet {
            userDefaults.set(promptMinute, forKey: Self.promptMinuteKey)
            Task {
                if isPromptEnabled {
                    await scheduleDailyPromptIfNeeded()
                }
            }
        }
    }

    private static let promptEnabledKey = "journalPromptEnabled"
    private static let promptHourKey = "journalPromptHour"
    private static let promptMinuteKey = "journalPromptMinute"
    private static let minimumEntriesForWeeklyRecap = 1
    private static let weeklyRecapFingerprintPrefix = "journalWeeklyRecapFingerprint."

    private let notesManager = NotesManager.shared
    private let notificationService = NotificationService.shared
    private let openAIService = GeminiService.shared
    private let userDefaults = UserDefaults.standard
    private var isGeneratingWeeklyRecap = false
    private let weekKeyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private init() {
        if userDefaults.object(forKey: Self.promptEnabledKey) == nil {
            userDefaults.set(true, forKey: Self.promptEnabledKey)
        }

        let storedHour = userDefaults.object(forKey: Self.promptHourKey) as? Int
        let storedMinute = userDefaults.object(forKey: Self.promptMinuteKey) as? Int

        self.isPromptEnabled = userDefaults.bool(forKey: Self.promptEnabledKey)
        self.promptHour = storedHour ?? 21
        self.promptMinute = storedMinute ?? 0
    }

    func entryForToday() -> Note? {
        notesManager.journalEntry(for: Date())
    }

    func prepareTodayDraft() -> JournalDraft {
        prepareDraft(for: Date())
    }

    func prepareTodayDraftEnsuringFolder() async -> JournalDraft {
        await prepareDraftEnsuringFolder(for: Date())
    }

    func prepareDraft(for date: Date) -> JournalDraft {
        buildDraft(for: date, folderId: notesManager.getOrCreateJournalFolder())
    }

    func prepareDraftEnsuringFolder(for date: Date) async -> JournalDraft {
        let folderId = await notesManager.getOrCreateJournalFolderAsync()
        return buildDraft(for: date, folderId: folderId)
    }

    func stats(referenceDate: Date = Date()) -> JournalStats {
        notesManager.journalStats(referenceDate: referenceDate)
    }

    func latestRecap() -> Note? {
        notesManager.latestJournalRecap()
    }

    func scheduleDailyPromptIfNeeded() async {
        guard isPromptEnabled else { return }
        await notificationService.scheduleDailyJournalPromptAt(hour: promptHour, minute: promptMinute)
    }

    func cancelDailyPrompt() {
        notificationService.cancelDailyJournalPrompt()
    }

    func ensureWeeklyRecapIfNeeded(referenceDate: Date = Date(), forceRefreshCurrentWeek: Bool = false) async {
        guard !isGeneratingWeeklyRecap else { return }

        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
              let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start),
              let previousWeekInterval = calendar.dateInterval(of: .weekOfYear, for: previousWeekStart) else {
            return
        }

        isGeneratingWeeklyRecap = true
        defer { isGeneratingWeeklyRecap = false }

        await upsertWeeklyRecap(
            for: previousWeekInterval,
            calendar: calendar,
            forceRefresh: false
        )
        await upsertWeeklyRecap(
            for: currentWeek,
            calendar: calendar,
            forceRefresh: forceRefreshCurrentWeek
        )
    }

    private func upsertWeeklyRecap(for weekInterval: DateInterval, calendar: Calendar, forceRefresh: Bool) async {
        let normalizedWeekStart = calendar.startOfDay(for: weekInterval.start)
        let weeklyEntries = notesManager.meaningfulJournalEntries
            .filter { entry in
                guard let journalDate = entry.journalDate else { return false }
                return weekInterval.contains(journalDate)
            }
            .sorted {
                ($0.journalDate ?? $0.dateModified) < ($1.journalDate ?? $1.dateModified)
            }

        guard weeklyEntries.count >= Self.minimumEntriesForWeeklyRecap else { return }

        let existingRecap = notesManager.journalWeeklyRecaps.first(where: { recap in
            guard let recapWeekStart = recap.journalWeekStartDate else { return false }
            return calendar.isDate(recapWeekStart, inSameDayAs: normalizedWeekStart)
        })
        let currentFingerprint = weeklyRecapFingerprint(for: weeklyEntries, calendar: calendar)
        let fingerprintKey = weeklyRecapFingerprintKey(for: normalizedWeekStart)
        let storedFingerprint = userDefaults.string(forKey: fingerprintKey)
        let hasExistingContent = !(existingRecap?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if !forceRefresh, let existingRecap, hasExistingContent {
            if storedFingerprint == currentFingerprint {
                return
            }

            if storedFingerprint == nil,
               !weeklyEntries.contains(where: { $0.dateModified > existingRecap.dateModified }) {
                userDefaults.set(currentFingerprint, forKey: fingerprintKey)
                return
            }
        }

        let folderId = await notesManager.getOrCreateJournalFolderAsync()
        let recapText: String
        do {
            let summaryInputs = weeklyEntries.map {
                JournalSummaryInput(
                    date: $0.journalDate ?? $0.dateModified,
                    title: $0.title,
                    preview: Self.previewText(for: $0),
                    mood: $0.journalMood
                )
            }
            recapText = try await openAIService.generateJournalWeeklySummary(entries: summaryInputs)
        } catch {
            recapText = fallbackWeeklySummary(for: weeklyEntries)
            print("⚠️ Falling back to deterministic journal recap: \(error.localizedDescription)")
        }

        if let existingRecap {
            var updatedRecap = existingRecap
            updatedRecap.title = Self.weeklyRecapTitle(for: normalizedWeekStart, calendar: calendar)
            updatedRecap.content = recapText
            updatedRecap.folderId = folderId
            updatedRecap.kind = .journalWeeklyRecap
            updatedRecap.journalWeekStartDate = normalizedWeekStart
            updatedRecap.isPinned = false
            updatedRecap.dateModified = Date()
            let _ = await notesManager.updateNoteAndWaitForSync(updatedRecap)
        } else {
            var recapNote = Note(
                title: Self.weeklyRecapTitle(for: normalizedWeekStart, calendar: calendar),
                content: recapText,
                folderId: folderId,
                kind: .journalWeeklyRecap,
                journalWeekStartDate: normalizedWeekStart
            )
            recapNote.isPinned = false

            let _ = await notesManager.addNoteAndWaitForSync(recapNote)
        }

        userDefaults.set(currentFingerprint, forKey: fingerprintKey)
    }

    func formatPromptTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        var components = DateComponents()
        components.hour = promptHour
        components.minute = promptMinute

        guard let date = Calendar.current.date(from: components) else {
            return "\(promptHour):\(String(format: "%02d", promptMinute))"
        }

        return formatter.string(from: date)
    }

    private func buildDraft(for date: Date, folderId: UUID) -> JournalDraft {
        JournalDraft(
            title: Self.journalEntryTitle(for: date),
            folderId: folderId,
            kind: .journalEntry,
            journalDate: Calendar.current.startOfDay(for: date)
        )
    }

    private func fallbackWeeklySummary(for entries: [Note]) -> String {
        let calendar = Calendar.current
        let completedDays = Set(entries.compactMap { $0.journalDate.map { calendar.startOfDay(for: $0) } }).count
        let firstEntryPreview = entries.first.map(Self.previewText(for:)) ?? "You started the week quietly."
        let lastEntryPreview = entries.last.map(Self.previewText(for:)) ?? "You kept the habit moving this week."
        let moodSummary = dominantMoodSummary(for: entries)

        return "You checked in on \(completedDays) day\(completedDays == 1 ? "" : "s") this week\(moodSummary). Early on, the week pointed toward \(firstEntryPreview). By the end, the thread that stood out most was \(lastEntryPreview)."
    }

    private static func journalEntryTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private static func weeklyRecapTitle(for weekStart: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Weekly Recap • \(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    private static func previewText(for note: Note) -> String {
        note.preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dominantMoodSummary(for entries: [Note]) -> String {
        let moods = entries.compactMap(\.journalMood)
        guard !moods.isEmpty else { return "" }

        let dominantMood = moods.reduce(into: [JournalMood: Int]()) { counts, mood in
            counts[mood, default: 0] += 1
        }
        .max { $0.value < $1.value }?
        .key

        guard let dominantMood else { return "" }
        return ", with the overall mood leaning \(dominantMood.title.lowercased())"
    }

    private func weeklyRecapFingerprint(for entries: [Note], calendar: Calendar) -> String {
        entries.map { entry in
            let journalDay = calendar.startOfDay(for: entry.journalDate ?? entry.dateModified).timeIntervalSince1970
            let mood = entry.journalMood?.rawValue ?? ""
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = entry.displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(entry.id.uuidString)|\(journalDay)|\(title)|\(mood)|\(content)"
        }
        .joined(separator: "\n")
    }

    private func weeklyRecapFingerprintKey(for weekStart: Date) -> String {
        Self.weeklyRecapFingerprintPrefix + weekKeyFormatter.string(from: weekStart)
    }
}
