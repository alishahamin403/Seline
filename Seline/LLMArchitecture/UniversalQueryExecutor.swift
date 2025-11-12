import Foundation

/// Core engine for executing semantic queries against any app data
class UniversalQueryExecutor {
    static let shared = UniversalQueryExecutor()

    private init() {}

    // MARK: - Main Execution

    /// Execute a semantic query and return structured results
    @MainActor
    func execute(_ query: SemanticQuery) async -> QueryResult {
        // Step 1: Fetch data from specified sources
        let data = fetchFromDataSources(query.dataSources)

        // Step 2: Apply filters
        let filtered = applyFilters(data, query.filters)

        // Step 3: Execute operations
        let resultData = if query.operations.isEmpty {
            QueryResultData(
                items: filtered,
                aggregations: [],
                comparisons: [],
                trends: []
            )
        } else {
            executeOperations(filtered, query.operations)
        }

        // Step 4: Generate explanation
        let explanation = generateExplanation(query, resultData)

        print("📊 Semantic Query Executed:")
        print("   Intent: \(query.intent)")
        print("   Sources: \(query.dataSources.count)")
        print("   Filtered items: \(filtered.count)")
        print("   Aggregations: \(resultData.aggregations.count)")
        print("   Confidence: \(String(format: "%.0f%%", query.confidence * 100))")

        return QueryResult(
            intent: query.intent,
            data: resultData,
            explanation: explanation
        )
    }

    // MARK: - Data Source Fetching

    /// Fetch data from specified sources using actual app managers and services
    @MainActor
    private func fetchFromDataSources(_ sources: [DataSource]) -> [UniversalItem] {
        var allItems: [UniversalItem] = []

        for source in sources {
            switch source {
            case .receipts(let category):
                // Fetch receipts - they are stored as notes in the Receipts folder
                // First, build ReceiptStat objects from notes
                let receiptNotes = NotesManager.shared.notes.filter { $0.folder == "Receipts" }
                var receipts: [ReceiptStat] = receiptNotes.map { note in
                    ReceiptStat(from: note, category: note.folder)
                }

                if let category = category {
                    receipts = receipts.filter { $0.category.lowercased() == category.lowercased() }
                }

                allItems.append(contentsOf: receipts.map { UniversalItem.receipt($0) })

            case .emails(let folder):
                // Combine inbox and sent emails from EmailService
                var emails = EmailService.shared.inboxEmails + EmailService.shared.sentEmails

                if let folder = folder {
                    emails = emails.filter { $0.folder.lowercased() == folder.lowercased() }
                }

                allItems.append(contentsOf: emails.map { UniversalItem.email($0) })

            case .events(let status):
                // Get events from TaskManager
                let allEvents = TaskManager.shared.tasks.values.flatMap { $0 }
                var filtered = allEvents

                if let status = status {
                    switch status {
                    case .upcoming:
                        filtered = filtered.filter { !$0.isCompleted }
                    case .completed:
                        filtered = filtered.filter { $0.isCompleted }
                    case .all:
                        break
                    }
                }

                allItems.append(contentsOf: filtered.map { UniversalItem.event($0) })

            case .notes(let folder):
                // Get notes from NotesManager
                var notes = NotesManager.shared.notes

                if let folder = folder {
                    notes = notes.filter { $0.folder.lowercased() == folder.lowercased() }
                }

                allItems.append(contentsOf: notes.map { UniversalItem.note($0) })

            case .locations(let filter):
                // Get locations from LocationsManager
                var locations = LocationsManager.shared.savedPlaces

                if let filter = filter {
                    switch filter {
                    case .favorited:
                        locations = locations.filter { $0.isFavorited }
                    case .ranked:
                        locations = locations.filter { $0.ranking > 0 }
                    case .inFolder:
                        locations = locations.filter { !$0.folder.isEmpty }
                    }
                }

                allItems.append(contentsOf: locations.map { UniversalItem.location($0) })

            case .calendar:
                // Get calendar events from TaskManager
                let events = TaskManager.shared.tasks.values.flatMap { $0 }
                allItems.append(contentsOf: events.map { UniversalItem.event($0) })
            }
        }

        return allItems
    }

    // MARK: - Filter Application

    /// Apply multiple filters to items
    private func applyFilters(_ items: [UniversalItem], _ filters: [AnyFilter]) -> [UniversalItem] {
        guard !filters.isEmpty else { return items }

        return items.filter { item in
            filters.allSatisfy { filter in
                filter.matches(item)
            }
        }
    }

    // MARK: - Operation Execution

    /// Execute all operations on the data
    private func executeOperations(_ items: [UniversalItem], _ operations: [AnyOperation]) -> QueryResultData {
        var result = QueryResultData(
            items: items,
            aggregations: [],
            comparisons: [],
            trends: []
        )

        for operation in operations {
            let opResult = operation.execute(on: items)
            result.aggregations.append(contentsOf: opResult.aggregations)
            result.comparisons.append(contentsOf: opResult.comparisons)
            result.trends.append(contentsOf: opResult.trends)
        }

        return result
    }

    // MARK: - Explanation Generation

    /// Generate natural language explanation of the query execution
    private func generateExplanation(_ query: SemanticQuery, _ result: QueryResultData) -> String {
        var parts: [String] = []

        // Explain what was searched
        let sourceDescriptions = query.dataSources.map { source in
            switch source {
            case .receipts(let category):
                return category.map { "receipts (category: \($0))" } ?? "all receipts"
            case .emails(let folder):
                return folder.map { "emails (folder: \($0))" } ?? "all emails"
            case .events(let status):
                return status.map { "events (\($0.rawValue))" } ?? "all events"
            case .notes(let folder):
                return folder.map { "notes (folder: \($0))" } ?? "all notes"
            case .locations(let filter):
                return filter.map { "locations (\($0.rawValue))" } ?? "all locations"
            case .calendar:
                return "calendar events"
            }
        }

        parts.append("Searched: \(sourceDescriptions.joined(separator: ", "))")

        // Explain filters applied
        if !query.filters.isEmpty {
            let filterDescriptions = query.filters.map { $0.description() }
            parts.append("Filtered by: \(filterDescriptions.joined(separator: "; "))")
        }

        // Explain operations
        if !query.operations.isEmpty {
            let operationDescriptions = query.operations.map { $0.description() }
            parts.append("Operations: \(operationDescriptions.joined(separator: "; "))")
        }

        // Explain results
        parts.append("Found: \(result.items.count) items")

        if !result.aggregations.isEmpty {
            parts.append("Aggregations: \(result.aggregations.count)")
        }

        if !result.comparisons.isEmpty {
            parts.append("Comparisons: \(result.comparisons.count)")
        }

        if !result.trends.isEmpty {
            parts.append("Trends: \(result.trends.count)")
        }

        return parts.joined(separator: " | ")
    }
}
