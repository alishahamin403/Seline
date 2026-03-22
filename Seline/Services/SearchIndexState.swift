import Combine
import Foundation

enum OverlaySearchResultType: String {
    case email
    case event
    case note
    case location
    case folder
    case receipt
    case recurringExpense
    case person

    var badgeLabel: String {
        switch self {
        case .email:
            return "Email"
        case .event:
            return "Event"
        case .note:
            return "Note"
        case .location:
            return "Place"
        case .folder:
            return "Folder"
        case .receipt:
            return "Receipt"
        case .recurringExpense:
            return "Recurring"
        case .person:
            return "Person"
        }
    }
}

struct OverlaySearchResult: Identifiable {
    let id: String
    let type: OverlaySearchResultType
    let title: String
    let subtitle: String
    let icon: String
    let task: TaskItem?
    let email: Email?
    let note: Note?
    let location: SavedPlace?
    let category: String?
    let person: Person?
    let recurringExpense: RecurringExpense?

    init(
        id: String? = nil,
        type: OverlaySearchResultType,
        title: String,
        subtitle: String,
        icon: String,
        task: TaskItem? = nil,
        email: Email? = nil,
        note: Note? = nil,
        location: SavedPlace? = nil,
        category: String? = nil,
        person: Person? = nil,
        recurringExpense: RecurringExpense? = nil
    ) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.task = task
        self.email = email
        self.note = note
        self.location = location
        self.category = category
        self.person = person
        self.recurringExpense = recurringExpense
        self.id = id ?? Self.defaultID(
            type: type,
            title: title,
            subtitle: subtitle,
            task: task,
            email: email,
            note: note,
            location: location,
            category: category,
            person: person,
            recurringExpense: recurringExpense
        )
    }

    private static func defaultID(
        type: OverlaySearchResultType,
        title: String,
        subtitle: String,
        task: TaskItem?,
        email: Email?,
        note: Note?,
        location: SavedPlace?,
        category: String?,
        person: Person?,
        recurringExpense: RecurringExpense?
    ) -> String {
        if let email {
            return "email-\(email.id)"
        }
        if let task {
            return "event-\(task.id)"
        }
        if let note {
            return "\(type.rawValue)-note-\(note.id.uuidString)"
        }
        if let location {
            return "\(type.rawValue)-place-\(location.id.uuidString)"
        }
        if let person {
            return "person-\(person.id.uuidString)"
        }
        if let recurringExpense {
            return "recurring-\(recurringExpense.id.uuidString)"
        }
        if let category, !category.isEmpty {
            return "\(type.rawValue)-category-\(category.lowercased().replacingOccurrences(of: " ", with: "-"))"
        }
        return "\(type.rawValue)-\(title.lowercased())-\(subtitle.lowercased())"
    }
}

struct SearchPreviewMetric: Identifiable, Equatable {
    let id: String
    let value: String
    let title: String
    let subtitle: String
    let icon: String
}

struct SearchPreviewHighlight: Identifiable {
    let id: String
    let eyebrow: String
    let result: OverlaySearchResult
}

struct SearchPreviewData {
    let metrics: [SearchPreviewMetric]
    let highlights: [SearchPreviewHighlight]

    static let empty = SearchPreviewData(metrics: [], highlights: [])
}

@MainActor
final class SearchIndexState: ObservableObject {
    enum Scope: CaseIterable, Hashable {
        case email
        case event
        case note
        case location
        case folder
        case receipt
        case recurringExpense
        case person
    }

    private struct IndexedEntry {
        let scope: Scope
        let result: OverlaySearchResult
        let normalizedFields: [String]
        let tieBreakTitle: String
        let basePriority: Int
    }

    static let shared = SearchIndexState()

    @Published private(set) var snapshotVersion: Int = 0
    @Published private(set) var preview = SearchPreviewData.empty

    private let emailService: EmailService
    private let taskManager: TaskManager
    private let notesManager: NotesManager
    private let locationsManager: LocationsManager
    private let peopleManager: PeopleManager
    private var cancellables = Set<AnyCancellable>()
    private var refreshGeneration = 0
    private var entriesByScope: [Scope: [IndexedEntry]] = [:]

    init(
        emailService: EmailService = .shared,
        taskManager: TaskManager = .shared,
        notesManager: NotesManager = .shared,
        locationsManager: LocationsManager = .shared,
        peopleManager: PeopleManager = .shared
    ) {
        self.emailService = emailService
        self.taskManager = taskManager
        self.notesManager = notesManager
        self.locationsManager = locationsManager
        self.peopleManager = peopleManager

        bind()
        refresh()
    }

    func refresh() {
        let inboxEmails = emailService.inboxEmails
        let sentEmails = emailService.sentEmails
        let tasks = taskManager.getAllFlattenedTasks()
        let notes = notesManager.notes
        let noteFolders = notesManager.folders
        let savedPlaces = locationsManager.savedPlaces
        let people = peopleManager.people
        let receiptSummaries = notesManager.getReceiptStatistics()
        let recurringExpenses: [RecurringExpense] =
            CacheManager.shared.get(forKey: CacheManager.CacheKey.allRecurringExpenses) ?? []

        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let receiptStats = receiptSummaries.flatMap { yearlySummary in
                yearlySummary.monthlySummaries.flatMap(\.receipts)
            }
            let nextEntries = Self.buildEntries(
                emails: inboxEmails + sentEmails,
                tasks: tasks,
                notes: notes,
                noteFolders: noteFolders,
                savedPlaces: savedPlaces,
                people: people,
                receipts: receiptStats,
                recurringExpenses: recurringExpenses
            )
            let nextPreview = Self.buildPreview(
                inboxEmails: inboxEmails,
                tasks: tasks,
                notes: notes,
                savedPlaces: savedPlaces,
                people: people,
                recurringExpenses: recurringExpenses
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation else { return }
                self.entriesByScope = nextEntries
                self.preview = nextPreview
                self.snapshotVersion &+= 1
            }
        }
    }

    func results(
        for query: String,
        scopes: Set<Scope>,
        limit: Int = 36
    ) -> [OverlaySearchResult] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var bestResultsById: [String: (result: OverlaySearchResult, score: Int, title: String)] = [:]

        for scope in scopes {
            for entry in entriesByScope[scope] ?? [] {
                guard let relevance = Self.relevanceScore(for: normalizedQuery, in: entry.normalizedFields) else {
                    continue
                }

                let score = relevance + entry.basePriority
                let existing = bestResultsById[entry.result.id]
                if existing == nil || score > existing!.score {
                    bestResultsById[entry.result.id] = (entry.result, score, entry.tieBreakTitle)
                }
            }
        }

        return bestResultsById.values
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.result)
    }

    private func bind() {
        emailService.$inboxEmails
            .merge(with: emailService.$sentEmails)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        taskManager.$tasks
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        notesManager.$notes
            .combineLatest(notesManager.$folders)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        locationsManager.$savedPlaces
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        peopleManager.$people
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private static func buildEntries(
        emails: [Email],
        tasks: [TaskItem],
        notes: [Note],
        noteFolders: [NoteFolder],
        savedPlaces: [SavedPlace],
        people: [Person],
        receipts: [ReceiptStat],
        recurringExpenses: [RecurringExpense]
    ) -> [Scope: [IndexedEntry]] {
        var entriesByScope: [Scope: [IndexedEntry]] = [:]
        let notesById = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let receiptNoteIds = Set(receipts.map(\.noteId))
        let folderParentById = Dictionary(uniqueKeysWithValues: noteFolders.map { ($0.id, $0.parentFolderId) })
        let receiptFolderIds = Set(
            noteFolders
                .filter { $0.name.caseInsensitiveCompare("Receipts") == .orderedSame }
                .map(\.id)
        )

        func append(_ entry: IndexedEntry) {
            entriesByScope[entry.scope, default: []].append(entry)
        }

        func isDescendantOfReceiptsFolder(note: Note) -> Bool {
            guard let folderId = note.folderId else { return false }
            var currentFolderId: UUID? = folderId

            while let currentId = currentFolderId {
                if receiptFolderIds.contains(currentId) {
                    return true
                }
                currentFolderId = folderParentById[currentId] ?? nil
            }

            return false
        }

        for email in emails {
            let title = email.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let senderName = email.sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = senderName.isEmpty ? email.sender.email : "from \(senderName)"

            append(
                IndexedEntry(
                    scope: .email,
                    result: OverlaySearchResult(
                        id: "email-\(email.id)",
                        type: .email,
                        title: title.isEmpty ? "(No subject)" : title,
                        subtitle: subtitle,
                        icon: "envelope",
                        task: nil,
                        email: email,
                        note: nil,
                        location: nil,
                        category: nil,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        email.subject,
                        email.sender.displayName,
                        email.sender.email,
                        email.snippet
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: title,
                    basePriority: 30
                )
            )
        }

        for task in tasks {
            append(
                IndexedEntry(
                    scope: .event,
                    result: OverlaySearchResult(
                        id: "task-\(task.id)",
                        type: .event,
                        title: task.title,
                        subtitle: eventSubtitle(for: task),
                        icon: "calendar",
                        task: task,
                        email: nil,
                        note: nil,
                        location: nil,
                        category: nil,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        task.title,
                        task.description ?? "",
                        task.location ?? "",
                        task.calendarTitle ?? "",
                        task.emailSubject ?? ""
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: task.title,
                    basePriority: 28
                )
            )
        }

        for receipt in receipts.sorted(by: { $0.date > $1.date }) {
            guard let linkedNote = notesById[receipt.noteId] else { continue }
            let dateString = shortDateString(receipt.date)

            append(
                IndexedEntry(
                    scope: .receipt,
                    result: OverlaySearchResult(
                        id: "receipt-\(receipt.noteId.uuidString)",
                        type: .receipt,
                        title: receipt.title,
                        subtitle: "\(formatCurrency(receipt.amount)) • \(dateString)",
                        icon: "doc.text",
                        task: nil,
                        email: nil,
                        note: linkedNote,
                        location: nil,
                        category: receipt.category,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        receipt.title,
                        receipt.category,
                        linkedNote.displayContent
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: receipt.title,
                    basePriority: 26
                )
            )
        }

        for note in notes where !receiptNoteIds.contains(note.id) && !isDescendantOfReceiptsFolder(note: note) {
            append(
                IndexedEntry(
                    scope: .note,
                    result: OverlaySearchResult(
                        id: "note-\(note.id.uuidString)",
                        type: .note,
                        title: note.title,
                        subtitle: shortDateTimeString(note.dateModified),
                        icon: note.isJournalWeeklyRecap ? "book.closed.fill" : (note.isJournalEntry ? "square.and.pencil" : "note.text"),
                        task: nil,
                        email: nil,
                        note: note,
                        location: nil,
                        category: nil,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        note.title,
                        note.displayContent
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: note.title,
                    basePriority: 24
                )
            )
        }

        let groupedPlacesByFolder = Dictionary(grouping: savedPlaces) { place in
            place.category.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for place in savedPlaces {
            append(
                IndexedEntry(
                    scope: .location,
                    result: OverlaySearchResult(
                        id: "place-\(place.id.uuidString)",
                        type: .location,
                        title: place.displayName,
                        subtitle: place.address,
                        icon: place.getDisplayIcon(),
                        task: nil,
                        email: nil,
                        note: nil,
                        location: place,
                        category: place.category,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        place.displayName,
                        place.address,
                        place.category,
                        place.city ?? "",
                        place.country ?? ""
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: place.displayName,
                    basePriority: 22
                )
            )
        }

        for (folderName, places) in groupedPlacesByFolder where !folderName.isEmpty {
            let subtitle = places.count == 1 ? "1 saved place" : "\(places.count) saved places"
            append(
                IndexedEntry(
                    scope: .folder,
                    result: OverlaySearchResult(
                        id: "folder-\(normalize(folderName))",
                        type: .folder,
                        title: folderName,
                        subtitle: subtitle,
                        icon: "folder.fill",
                        task: nil,
                        email: nil,
                        note: nil,
                        location: nil,
                        category: folderName,
                        person: nil,
                        recurringExpense: nil
                    ),
                    normalizedFields: [normalize(folderName)],
                    tieBreakTitle: folderName,
                    basePriority: 20
                )
            )
        }

        for person in people {
            append(
                IndexedEntry(
                    scope: .person,
                    result: OverlaySearchResult(
                        id: "person-\(person.id.uuidString)",
                        type: .person,
                        title: person.displayName,
                        subtitle: person.relationshipDisplayText,
                        icon: person.getDisplayIcon(),
                        task: nil,
                        email: nil,
                        note: nil,
                        location: nil,
                        category: nil,
                        person: person,
                        recurringExpense: nil
                    ),
                    normalizedFields: [
                        person.name,
                        person.nickname ?? "",
                        person.email ?? "",
                        person.notes ?? "",
                        person.relationshipDisplayText,
                        person.favouriteFood ?? "",
                        person.favouriteGift ?? ""
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: person.displayName,
                    basePriority: 18
                )
            )
        }

        for expense in recurringExpenses {
            append(
                IndexedEntry(
                    scope: .recurringExpense,
                    result: OverlaySearchResult(
                        id: "recurring-\(expense.id.uuidString)",
                        type: .recurringExpense,
                        title: expense.title,
                        subtitle: "\(formatCurrency(Double(truncating: expense.amount as NSDecimalNumber))) • Next \(shortDateString(expense.nextOccurrence))",
                        icon: "repeat.circle",
                        task: nil,
                        email: nil,
                        note: nil,
                        location: nil,
                        category: expense.category,
                        person: nil,
                        recurringExpense: expense
                    ),
                    normalizedFields: [
                        expense.title,
                        expense.category ?? "",
                        expense.description ?? ""
                    ].map(normalize).filter { !$0.isEmpty },
                    tieBreakTitle: expense.title,
                    basePriority: 16
                )
            )
        }

        return entriesByScope
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func relevanceScore(for query: String, in fields: [String]) -> Int? {
        var bestScore: Int?

        for field in fields where !field.isEmpty {
            let score: Int?
            if field == query {
                score = 450
            } else if field.hasPrefix(query) {
                score = 360
            } else if field.contains(" \(query)") {
                score = 260
            } else if field.contains(query) {
                score = 180
            } else {
                score = nil
            }

            if let score {
                bestScore = max(bestScore ?? 0, score)
            }
        }

        return bestScore
    }

    private static func eventSubtitle(for task: TaskItem) -> String {
        if let targetDate = task.targetDate {
            if let scheduledTime = task.scheduledTime {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
                if let combinedDate = calendar.date(
                    bySettingHour: timeComponents.hour ?? 0,
                    minute: timeComponents.minute ?? 0,
                    second: timeComponents.second ?? 0,
                    of: targetDate
                ) {
                    return shortDateTimeString(combinedDate)
                }
            }

            return shortDateString(targetDate)
        }

        if let scheduledTime = task.scheduledTime {
            return shortDateTimeString(scheduledTime)
        }

        return "No date set"
    }

    private static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private static func shortDateTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private static func buildPreview(
        inboxEmails: [Email],
        tasks: [TaskItem],
        notes: [Note],
        savedPlaces: [SavedPlace],
        people: [Person],
        recurringExpenses: [RecurringExpense]
    ) -> SearchPreviewData {
        let unreadEmails = inboxEmails.filter { !$0.isRead }
        let openTasks = tasks.filter { !$0.isCompleted && !$0.isDeleted }

        let metrics = [
            SearchPreviewMetric(
                id: "unread-emails",
                value: "\(unreadEmails.count)",
                title: "Unread Emails",
                subtitle: unreadEmails.count == 1 ? "Waiting in inbox" : "Waiting in inbox",
                icon: "envelope.badge"
            ),
            SearchPreviewMetric(
                id: "open-events",
                value: "\(openTasks.count)",
                title: "Open Events",
                subtitle: openTasks.count == 1 ? "Still on deck" : "Still on deck",
                icon: "calendar.badge.clock"
            ),
            SearchPreviewMetric(
                id: "notes",
                value: "\(notes.count)",
                title: "Notes",
                subtitle: notes.count == 1 ? "Ready to search" : "Ready to search",
                icon: "note.text"
            ),
            SearchPreviewMetric(
                id: "places-people",
                value: "\(savedPlaces.count + people.count)",
                title: "Places + People",
                subtitle: "Saved context",
                icon: "square.grid.2x2"
            )
        ]

        var highlights: [SearchPreviewHighlight] = []

        if let email = (unreadEmails.isEmpty ? inboxEmails : unreadEmails)
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-email-\(email.id)",
                    eyebrow: unreadEmails.isEmpty ? "Latest Inbox Email" : "Latest Unread Email",
                    result: previewResult(for: email)
                )
            )
        }

        if let task = openTasks
            .sorted(by: { eventSortDate(for: $0) < eventSortDate(for: $1) })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-task-\(task.id)",
                    eyebrow: "Up Next",
                    result: previewResult(for: task)
                )
            )
        }

        if let note = notes
            .sorted(by: { $0.dateModified > $1.dateModified })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-note-\(note.id.uuidString)",
                    eyebrow: "Recently Edited",
                    result: previewResult(for: note)
                )
            )
        }

        if let place = savedPlaces
            .sorted(by: { $0.dateModified > $1.dateModified })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-place-\(place.id.uuidString)",
                    eyebrow: place.isFavourite ? "Favorite Place" : "Recently Saved Place",
                    result: previewResult(for: place)
                )
            )
        } else if let person = people
            .sorted(by: { $0.dateModified > $1.dateModified })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-person-\(person.id.uuidString)",
                    eyebrow: "People Update",
                    result: previewResult(for: person)
                )
            )
        } else if let expense = recurringExpenses
            .sorted(by: { $0.nextOccurrence < $1.nextOccurrence })
            .first
        {
            highlights.append(
                SearchPreviewHighlight(
                    id: "highlight-recurring-\(expense.id.uuidString)",
                    eyebrow: "Coming Up",
                    result: previewResult(for: expense)
                )
            )
        }

        return SearchPreviewData(
            metrics: metrics,
            highlights: Array(highlights.prefix(4))
        )
    }

    private static func previewResult(for email: Email) -> OverlaySearchResult {
        let title = email.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderName = email.sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = senderName.isEmpty ? email.sender.email : "from \(senderName)"

        return OverlaySearchResult(
            id: "email-\(email.id)",
            type: .email,
            title: title.isEmpty ? "(No subject)" : title,
            subtitle: subtitle,
            icon: "envelope",
            email: email
        )
    }

    private static func previewResult(for task: TaskItem) -> OverlaySearchResult {
        OverlaySearchResult(
            id: "task-\(task.id)",
            type: .event,
            title: task.title,
            subtitle: eventSubtitle(for: task),
            icon: "calendar",
            task: task
        )
    }

    private static func previewResult(for note: Note) -> OverlaySearchResult {
        OverlaySearchResult(
            id: "note-\(note.id.uuidString)",
            type: .note,
            title: note.title,
            subtitle: shortDateTimeString(note.dateModified),
            icon: note.isJournalWeeklyRecap ? "book.closed.fill" : (note.isJournalEntry ? "square.and.pencil" : "note.text"),
            note: note
        )
    }

    private static func previewResult(for place: SavedPlace) -> OverlaySearchResult {
        OverlaySearchResult(
            id: "place-\(place.id.uuidString)",
            type: .location,
            title: place.displayName,
            subtitle: place.address,
            icon: place.getDisplayIcon(),
            location: place,
            category: place.category
        )
    }

    private static func previewResult(for person: Person) -> OverlaySearchResult {
        OverlaySearchResult(
            id: "person-\(person.id.uuidString)",
            type: .person,
            title: person.displayName,
            subtitle: person.relationshipDisplayText,
            icon: person.getDisplayIcon(),
            person: person
        )
    }

    private static func previewResult(for expense: RecurringExpense) -> OverlaySearchResult {
        OverlaySearchResult(
            id: "recurring-\(expense.id.uuidString)",
            type: .recurringExpense,
            title: expense.title,
            subtitle: "\(formatCurrency(Double(truncating: expense.amount as NSDecimalNumber))) • Next \(shortDateString(expense.nextOccurrence))",
            icon: "repeat.circle",
            recurringExpense: expense
        )
    }

    private static func eventSortDate(for task: TaskItem) -> Date {
        if let targetDate = task.targetDate {
            if let scheduledTime = task.scheduledTime {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
                if let combinedDate = calendar.date(
                    bySettingHour: timeComponents.hour ?? 0,
                    minute: timeComponents.minute ?? 0,
                    second: timeComponents.second ?? 0,
                    of: targetDate
                ) {
                    return combinedDate
                }
            }

            return targetDate
        }

        return task.scheduledTime ?? task.createdAt
    }
}

extension Set where Element == SearchIndexState.Scope {
    static let searchPageScopes: Set<SearchIndexState.Scope> = [
        .email,
        .event,
        .note,
        .location,
        .folder,
        .receipt,
        .recurringExpense,
        .person
    ]

    static let homeSearchScopes: Set<SearchIndexState.Scope> = [
        .email,
        .event,
        .note,
        .location,
        .folder,
        .receipt,
        .recurringExpense,
        .person
    ]

    static let overlaySearchScopes: Set<SearchIndexState.Scope> = [
        .email,
        .event,
        .note,
        .location,
        .folder,
        .receipt,
        .recurringExpense
    ]
}
