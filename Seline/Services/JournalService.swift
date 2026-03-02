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
    private static let minimumEntriesForWeeklyRecap = 3

    private let notesManager = NotesManager.shared
    private let notificationService = NotificationService.shared
    private let openAIService = GeminiService.shared
    private let userDefaults = UserDefaults.standard
    private var isGeneratingWeeklyRecap = false

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
        prepareDraft(for: Date(), folderId: notesManager.getOrCreateJournalFolder())
    }

    func prepareTodayDraftEnsuringFolder() async -> JournalDraft {
        let folderId = await notesManager.getOrCreateJournalFolderAsync()
        return prepareDraft(for: Date(), folderId: folderId)
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

    func ensureWeeklyRecapIfNeeded(referenceDate: Date = Date()) async {
        guard !isGeneratingWeeklyRecap else { return }

        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
              let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start),
              let previousWeekInterval = calendar.dateInterval(of: .weekOfYear, for: previousWeekStart) else {
            return
        }

        let normalizedWeekStart = calendar.startOfDay(for: previousWeekInterval.start)
        if notesManager.journalWeeklyRecaps.contains(where: { recap in
            guard let recapWeekStart = recap.journalWeekStartDate else { return false }
            return calendar.isDate(recapWeekStart, inSameDayAs: normalizedWeekStart)
        }) {
            return
        }

        let weeklyEntries = notesManager.journalEntries
            .filter { entry in
                guard let journalDate = entry.journalDate else { return false }
                return previousWeekInterval.contains(journalDate)
            }
            .sorted {
                ($0.journalDate ?? $0.dateModified) < ($1.journalDate ?? $1.dateModified)
            }

        guard weeklyEntries.count >= Self.minimumEntriesForWeeklyRecap else { return }

        isGeneratingWeeklyRecap = true
        defer { isGeneratingWeeklyRecap = false }

        let folderId = await notesManager.getOrCreateJournalFolderAsync()
        let recapText: String
        do {
            let summaryInputs = weeklyEntries.map {
                JournalSummaryInput(
                    date: $0.journalDate ?? $0.dateModified,
                    title: $0.title,
                    preview: Self.previewText(for: $0)
                )
            }
            recapText = try await openAIService.generateJournalWeeklySummary(entries: summaryInputs)
        } catch {
            recapText = fallbackWeeklySummary(for: weeklyEntries)
            print("⚠️ Falling back to deterministic journal recap: \(error.localizedDescription)")
        }

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

    private func prepareDraft(for date: Date, folderId: UUID) -> JournalDraft {
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
        let lastEntryPreview = entries.last.map(Self.previewText(for:)) ?? "You kept the habit moving this week."
        return "You journaled on \(completedDays) day\(completedDays == 1 ? "" : "s") this week. The overall thread was consistency and reflection across the week. Last note highlight: \(lastEntryPreview)"
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
}
