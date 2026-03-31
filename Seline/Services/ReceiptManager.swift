import Combine
import Foundation
import PostgREST
import UIKit

@MainActor
final class ReceiptManager: ObservableObject {
    static let shared = ReceiptManager()

    @Published private(set) var nativeReceipts: [ReceiptStat] = []
    @Published private(set) var receipts: [ReceiptStat] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastMigrationError: String?

    private let notesManager: NotesManager
    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "NativeReceipts.v2"
    private var didAttemptRemoteLoad = false
    private var migrationTask: Task<Void, Never>?

    private init(notesManager: NotesManager = .shared) {
        self.notesManager = notesManager
        loadNativeReceiptsFromStorage()
        rebuildUnifiedReceipts()
        bind()

        Task {
            await ensureLoaded()
        }
    }

    func ensureLoaded() async {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else {
            await migrateLegacyReceiptsIfNeeded()
            scheduleLegacyMigration()
            return
        }

        guard !didAttemptRemoteLoad else {
            await migrateLegacyReceiptsIfNeeded()
            scheduleLegacyMigration()
            return
        }

        didAttemptRemoteLoad = true
        await loadNativeReceiptsFromSupabase()
        await migrateLegacyReceiptsIfNeeded()
        scheduleLegacyMigration()
    }

    func receipt(by id: UUID) -> ReceiptStat? {
        receipts.first(where: { $0.id == id || $0.noteId == id })
    }

    func note(for receipt: ReceiptStat) -> Note? {
        guard let legacyNoteId = receipt.legacyNoteId else { return nil }
        return notesManager.notes.first(where: { $0.id == legacyNoteId })
    }

    func isHiddenMigratedReceiptNote(_ noteId: UUID) -> Bool {
        nativeReceipts.contains(where: { $0.legacyNoteId == noteId })
    }

    func visibleNotes(_ notes: [Note]) -> [Note] {
        notes.filter { !isHiddenMigratedReceiptNote($0.id) }
    }

    func receiptStatistics(year: Int? = nil) -> [YearlyReceiptSummary] {
        let relevantReceipts = receipts.filter { receipt in
            guard let year else { return true }
            return receipt.year == year
        }

        guard !relevantReceipts.isEmpty else { return [] }

        let calendar = Calendar.current
        struct MonthBucket: Hashable {
            let label: String
            let monthDate: Date
        }
        let groupedByYear = Dictionary(grouping: relevantReceipts) { receipt in
            receipt.year ?? calendar.component(.year, from: receipt.date)
        }

        return groupedByYear
            .map { year, receipts in
                let groupedByMonth = Dictionary(grouping: receipts) { receipt -> MonthBucket in
                    let monthDate: Date
                    if let month = receipt.month,
                       let monthIndex = calendar.monthSymbols.firstIndex(of: month) {
                        var components = DateComponents()
                        components.year = year
                        components.month = monthIndex + 1
                        components.day = 1
                        monthDate = calendar.date(from: components) ?? receipt.date
                    } else {
                        monthDate = receipt.date
                    }

                    let monthLabel = receipt.month ?? calendar.monthSymbols[calendar.component(.month, from: monthDate) - 1]
                    return MonthBucket(
                        label: monthLabel,
                        monthDate: calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
                    )
                }

                let monthlySummaries = groupedByMonth.map { key, receipts in
                    MonthlyReceiptSummary(month: key.label, monthDate: key.monthDate, receipts: receipts)
                }

                return YearlyReceiptSummary(year: year, monthlySummaries: monthlySummaries)
            }
            .sorted { $0.year > $1.year }
    }

    func availableYears() -> [Int] {
        receiptStatistics().map(\.year).sorted(by: >)
    }

    func categoryBreakdown(for year: Int) async -> YearlyCategoryBreakdown {
        let receiptsForYear = receiptStatistics(year: year)
            .first?
            .monthlySummaries
            .flatMap(\.receipts) ?? []

        guard !receiptsForYear.isEmpty else {
            return YearlyCategoryBreakdown(year: year, categories: [], yearlyTotal: 0)
        }

        return await ReceiptCategorizationService.shared.getCategoryBreakdown(for: receiptsForYear)
    }

    func createReceipt(from draft: ReceiptDraft, images: [UIImage] = [], id: UUID = UUID(), source: ReceiptSource = .native, legacyNoteId: UUID? = nil) async throws -> ReceiptStat {
        let uploadedImageURLs = try await uploadReceiptImages(images, receiptId: id)
        let mergedImageURLs = uploadedImageURLs.isEmpty ? draft.imageUrls : uploadedImageURLs
        let normalized = normalizedDraft(draft, fallbackDate: Date())
        let receipt = makeReceipt(
            id: id,
            source: source,
            legacyNoteId: legacyNoteId,
            draft: ReceiptDraft(
                merchant: normalized.merchant,
                total: normalized.total,
                transactionDate: normalized.transactionDate,
                transactionTime: normalized.transactionTime,
                category: normalized.category,
                subtotal: normalized.subtotal,
                tax: normalized.tax,
                tip: normalized.tip,
                paymentMethod: normalized.paymentMethod,
                detailFields: normalized.detailFields,
                lineItems: normalized.lineItems,
                imageUrls: mergedImageURLs
            )
        )

        nativeReceipts.removeAll { $0.id == receipt.id }
        nativeReceipts.append(receipt)
        nativeReceipts.sort { $0.date > $1.date }
        persistNativeReceiptsToStorage()
        rebuildUnifiedReceipts()

        Task {
            await self.upsertReceiptToSupabase(receipt)
        }

        return receipt
    }

    private func bind() {
        notesManager.$notes
            .combineLatest(notesManager.$folders)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.rebuildUnifiedReceipts()
                self?.scheduleLegacyMigration()
            }
            .store(in: &cancellables)
    }

    private func rebuildUnifiedReceipts() {
        let migratedLegacyIDs = Set(nativeReceipts.compactMap(\.legacyNoteId))
        let fallbackLegacyReceipts = legacyReceiptCandidateNotes()
            .filter { !migratedLegacyIDs.contains($0.id) }
            .map { makeReceipt(from: $0, source: .legacyFallback) }

        let combined = nativeReceipts + fallbackLegacyReceipts
        var deduped: [UUID: ReceiptStat] = [:]
        for receipt in combined.sorted(by: { $0.date > $1.date }) {
            deduped[receipt.id] = receipt
        }

        receipts = deduped.values.sorted { $0.date > $1.date }
        invalidateCaches()
    }

    private func scheduleLegacyMigration() {
        migrationTask?.cancel()
        migrationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.migrateLegacyReceiptsIfNeeded()
        }
    }

    private func migrateLegacyReceiptsIfNeeded() async {
        let existingLegacyIDs = Set(nativeReceipts.compactMap(\.legacyNoteId))
        let candidates = legacyReceiptCandidateNotes().filter { !existingLegacyIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        var migratedAny = false
        for note in candidates {
            let migratedReceipt = makeReceipt(from: note, source: .migratedLegacy)
            nativeReceipts.removeAll { $0.id == migratedReceipt.id }
            nativeReceipts.append(migratedReceipt)
            nativeReceipts.sort { $0.date > $1.date }
            migratedAny = true
            await upsertReceiptToSupabase(migratedReceipt)
        }

        guard migratedAny else { return }
        persistNativeReceiptsToStorage()
        rebuildUnifiedReceipts()
    }

    private func loadNativeReceiptsFromStorage() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([ReceiptStat].self, from: data)
        else {
            nativeReceipts = []
            return
        }

        nativeReceipts = decoded.sorted { $0.date > $1.date }
    }

    private func persistNativeReceiptsToStorage() {
        guard let data = try? JSONEncoder().encode(nativeReceipts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadNativeReceiptsFromSupabase() async {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [ReceiptSupabaseData] = try await client
                .from("receipts")
                .select()
                .order("date", ascending: false)
                .execute()
                .value

            let decoded = response.compactMap { $0.toReceiptStat() }
            guard !decoded.isEmpty else { return }

            nativeReceipts = mergeStoredAndRemoteReceipts(local: nativeReceipts, remote: decoded)
            persistNativeReceiptsToStorage()
            rebuildUnifiedReceipts()
        } catch {
            print("❌ Error loading receipts from Supabase: \(error)")
        }
    }

    private func mergeStoredAndRemoteReceipts(local: [ReceiptStat], remote: [ReceiptStat]) -> [ReceiptStat] {
        var merged: [UUID: ReceiptStat] = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for receipt in remote {
            merged[receipt.id] = receipt
        }
        return merged.values.sorted { $0.date > $1.date }
    }

    private func upsertReceiptToSupabase(_ receipt: ReceiptStat) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }

        do {
            let payload = try receipt.toSupabasePayload(userId: userId)
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("receipts")
                .upsert(payload, onConflict: "id")
                .execute()
        } catch {
            print("❌ Error saving receipt to Supabase: \(error)")
            lastMigrationError = error.localizedDescription
        }
    }

    private func uploadReceiptImages(_ images: [UIImage], receiptId: UUID) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return [] }

        var urls: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.82) else { continue }
            let fileName = "receipts/\(receiptId.uuidString)-\(index).jpg"
            let url = try await SupabaseManager.shared.uploadImage(data, fileName: fileName, userId: userId)
            urls.append(url)
        }
        return urls
    }

    private func legacyReceiptCandidateNotes() -> [Note] {
        let foldersById = Dictionary(uniqueKeysWithValues: notesManager.folders.map { ($0.id, $0) })
        let receiptRootIds = Set(
            notesManager.folders
                .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "receipts" }
                .map(\.id)
        )

        var candidates = notesManager.notes.filter { note in
            isUnderReceiptHierarchy(folderId: note.folderId, receiptRootIds: receiptRootIds, foldersById: foldersById)
        }

        if receiptRootIds.isEmpty || candidates.isEmpty {
            let existing = Set(candidates.map(\.id))
            candidates.append(
                contentsOf: notesManager.notes.filter { note in
                    !existing.contains(note.id) && isReceiptLike(note)
                }
            )
        }

        return candidates
    }

    private func isUnderReceiptHierarchy(folderId: UUID?, receiptRootIds: Set<UUID>, foldersById: [UUID: NoteFolder]) -> Bool {
        guard let folderId, !receiptRootIds.isEmpty else { return false }
        var currentFolderId: UUID? = folderId
        while let current = currentFolderId {
            if receiptRootIds.contains(current) {
                return true
            }
            currentFolderId = foldersById[current]?.parentFolderId
        }
        return false
    }

    private func isReceiptLike(_ note: Note) -> Bool {
        let combined = "\(note.title)\n\(note.content)".lowercased()
        let keywords = [
            "receipt",
            "subtotal",
            "total",
            "merchant",
            "payment",
            "transaction",
            "tax",
            "tip"
        ]

        let hasKeyword = keywords.contains { combined.contains($0) }
        let hasAttachment = !note.imageUrls.isEmpty || note.attachmentId != nil
        let hasParsedDate = notesManager.extractFullDateFromTitle(note.title) != nil || notesManager.extractMonthYearFromTitle(note.title) != nil
        let amount = CurrencyParser.extractAmount(from: combined)
        return amount > 0 && (hasKeyword || hasAttachment || hasParsedDate)
    }

    private func makeReceipt(from note: Note, source: ReceiptSource) -> ReceiptStat {
        let normalized = parseLegacyReceiptDraft(from: note)
        let effectiveDate = normalized.transactionDate
        let year = Calendar.current.component(.year, from: effectiveDate)
        let month = Calendar.current.monthSymbols[Calendar.current.component(.month, from: effectiveDate) - 1]

        return ReceiptStat(
            id: note.id,
            source: source,
            title: normalized.resolvedTitle,
            merchant: normalized.resolvedMerchant,
            amount: normalized.total,
            date: normalized.transactionDate,
            transactionTime: normalized.transactionTime,
            noteId: note.id,
            legacyNoteId: note.id,
            year: year,
            month: month,
            category: normalized.category,
            subtotal: normalized.subtotal,
            tax: normalized.tax,
            tip: normalized.tip,
            paymentMethod: normalized.paymentMethod,
            imageUrls: note.imageUrls,
            detailFields: normalized.detailFields,
            lineItems: normalized.lineItems
        )
    }

    private func makeReceipt(id: UUID, source: ReceiptSource, legacyNoteId: UUID?, draft: ReceiptDraft) -> ReceiptStat {
        let normalized = normalizedDraft(draft, fallbackDate: Date())
        let calendar = Calendar.current
        let year = calendar.component(.year, from: normalized.transactionDate)
        let month = calendar.monthSymbols[calendar.component(.month, from: normalized.transactionDate) - 1]

        return ReceiptStat(
            id: id,
            source: source,
            title: normalized.resolvedTitle,
            merchant: normalized.resolvedMerchant,
            amount: normalized.total,
            date: normalized.transactionDate,
            transactionTime: normalized.transactionTime,
            noteId: id,
            legacyNoteId: legacyNoteId,
            year: year,
            month: month,
            category: normalized.category,
            subtotal: normalized.subtotal,
            tax: normalized.tax,
            tip: normalized.tip,
            paymentMethod: normalized.paymentMethod,
            imageUrls: normalized.imageUrls,
            detailFields: normalized.detailFields,
            lineItems: normalized.lineItems
        )
    }

    private func normalizedDraft(_ draft: ReceiptDraft, fallbackDate: Date) -> ReceiptDraft {
        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Receipt" : draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = draft.transactionDate
        var fields = draft.detailFields.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var existingLabels = Set(fields.map { $0.label.lowercased() })

        func appendField(label: String, value: String?, kind: ReceiptFieldKind) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            guard !existingLabels.contains(label.lowercased()) else { return }
            fields.append(ReceiptField(label: label, value: value, kind: kind))
            existingLabels.insert(label.lowercased())
        }

        let timeValue = draft.transactionTime.map { FormatterCache.shortTime.string(from: $0) }
        appendField(label: "Time", value: timeValue, kind: .time)
        appendField(label: "Payment", value: draft.paymentMethod, kind: .text)
        appendField(label: "Subtotal", value: draft.subtotal.map { CurrencyParser.formatAmount($0) }, kind: .currency)
        appendField(label: "Tax", value: draft.tax.map { CurrencyParser.formatAmount($0) }, kind: .currency)
        appendField(label: "Tip", value: draft.tip.map { CurrencyParser.formatAmount($0) }, kind: .currency)

        return ReceiptDraft(
            merchant: merchant,
            total: draft.total,
            transactionDate: draft.transactionDate == .distantPast ? fallbackDate : date,
            transactionTime: draft.transactionTime,
            category: draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : draft.category,
            subtotal: draft.subtotal,
            tax: draft.tax,
            tip: draft.tip,
            paymentMethod: draft.paymentMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
            detailFields: fields,
            lineItems: draft.lineItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            imageUrls: draft.imageUrls
        )
    }

    private func parseLegacyReceiptDraft(from note: Note) -> ReceiptDraft {
        let contentLines = note.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchant = ReceiptStat.extractMerchantName(from: note.title)
        let parsedDate = notesManager.extractFullDateFromTitle(note.title) ?? note.dateModified
        let paymentMethod = value(afterAnyOf: ["payment", "method"], in: contentLines)
        let subtotal = labeledCurrency(["subtotal"], in: contentLines)
        let tax = labeledCurrency(["tax"], in: contentLines)
        let tip = labeledCurrency(["tip"], in: contentLines)
        let total = labeledCurrency(["total"], in: contentLines)
            ?? CurrencyParser.extractAmount(from: [note.title, note.content].joined(separator: "\n"))
        let timeText = value(afterAnyOf: ["time"], in: contentLines)
        let transactionTime = parseTime(text: timeText, using: parsedDate)

        let legacyFields = extractDetailFields(from: contentLines, excluding: ["items purchased", "summary", "additional info"])
        let lineItems = extractLineItems(from: contentLines)
        let category = ReceiptCategorizationService.shared.quickCategorizeReceipt(title: note.title, content: note.content) ?? "Other"

        return ReceiptDraft(
            merchant: merchant,
            total: total,
            transactionDate: parsedDate,
            transactionTime: transactionTime,
            category: category,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            paymentMethod: paymentMethod,
            detailFields: legacyFields,
            lineItems: lineItems,
            imageUrls: note.imageUrls
        )
    }

    private func labeledCurrency(_ labels: [String], in lines: [String]) -> Double? {
        lines.first(where: { line in
            let lower = line.lowercased()
            return labels.contains(where: { lower.contains($0.lowercased()) })
        }).map { CurrencyParser.extractAmount(from: $0) }.flatMap { $0 > 0 ? $0 : nil }
    }

    private func value(afterAnyOf labels: [String], in lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            guard labels.contains(where: { lowered.contains($0.lowercased()) }) else { continue }
            if let range = line.range(of: ":") {
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value.caseInsensitiveCompare("n/a") != .orderedSame {
                    return value
                }
            }
        }
        return nil
    }

    private func parseTime(text: String?, using date: Date) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let formatters = ["h:mm a", "hh:mm a", "H:mm", "HH:mm"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let parsedTime = formatter.date(from: text) {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: parsedTime)
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                return calendar.date(from: dateComponents)
            }
        }
        return nil
    }

    private func extractDetailFields(from lines: [String], excluding excludedLabels: [String]) -> [ReceiptField] {
        var fields: [ReceiptField] = []

        for line in lines {
            guard let separatorRange = line.range(of: ":") else { continue }
            let label = line[..<separatorRange.lowerBound]
                .replacingOccurrences(of: "📍", with: "")
                .replacingOccurrences(of: "💳", with: "")
                .replacingOccurrences(of: "💰", with: "")
                .replacingOccurrences(of: "📊", with: "")
                .replacingOccurrences(of: "💵", with: "")
                .replacingOccurrences(of: "✅", with: "")
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerLabel = label.lowercased()
            guard !label.isEmpty, !excludedLabels.contains(lowerLabel) else { continue }

            let value = String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.caseInsensitiveCompare("n/a") != .orderedSame else { continue }

            let kind: ReceiptFieldKind
            if lowerLabel.contains("date") {
                kind = .date
            } else if lowerLabel.contains("time") {
                kind = .time
            } else if CurrencyParser.extractAmount(from: value) > 0 {
                kind = .currency
            } else {
                kind = .text
            }

            fields.append(ReceiptField(label: label, value: value, kind: kind))
        }

        return fields
    }

    private func extractLineItems(from lines: [String]) -> [ReceiptLineItem] {
        var items: [ReceiptLineItem] = []
        let ignoredFragments = ["subtotal", "tax", "tip", "total", "merchant", "payment", "time", "summary", "additional info"]

        for line in lines {
            let normalized = line
                .replacingOccurrences(of: "•", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = normalized.lowercased()
            guard !ignoredFragments.contains(where: { lowered.contains($0) }) else { continue }
            let amount = CurrencyParser.extractAmount(from: normalized)
            guard amount > 0 else { continue }

            let title = normalized
                .replacingOccurrences(of: "\\$?\\d+[\\.,]?\\d*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            items.append(ReceiptLineItem(title: title, amount: amount))
        }

        return Array(items.prefix(16))
    }

    private func invalidateCaches() {
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.receiptStatsAll)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.lastKnownReceiptStatsAll)
        CacheManager.shared.invalidate(keysWithPrefix: "cache.receipts.stats.")
        CacheManager.shared.invalidate(keysWithPrefix: "cache.receipts.categoryBreakdown.")
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysReceipts)
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysSpending)
        MetadataBuilderService.invalidateCache()

        DispatchQueue.main.async {
            SpendingAndETAWidget.refreshWidgetSpendingData()
        }
    }
}

private struct ReceiptSupabaseData: Codable {
    let id: String
    let source: String
    let legacy_note_id: String?
    let title: String
    let merchant: String?
    let amount: Double
    let date: String
    let transaction_time: String?
    let category: String?
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let payment_method: String?
    let image_urls: [String]?
    let detail_fields: [ReceiptField]?
    let line_items: [ReceiptLineItem]?
    let year: Int?
    let month: String?

    func toReceiptStat() -> ReceiptStat? {
        guard
            let id = UUID(uuidString: id),
            let source = ReceiptSource(rawValue: source),
            let parsedDate = ReceiptISO8601.parse(date)
        else {
            return nil
        }

        let parsedTransactionTime = ReceiptISO8601.parse(transaction_time)
        let legacyNoteId = legacy_note_id.flatMap(UUID.init(uuidString:))

        return ReceiptStat(
            id: id,
            source: source,
            title: title,
            merchant: merchant,
            amount: amount,
            date: parsedDate,
            transactionTime: parsedTransactionTime,
            noteId: id,
            legacyNoteId: legacyNoteId,
            year: year,
            month: month,
            category: category ?? "Other",
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            paymentMethod: payment_method,
            imageUrls: image_urls ?? [],
            detailFields: detail_fields ?? [],
            lineItems: line_items ?? []
        )
    }
}

private enum ReceiptISO8601 {
    static func parse(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatterWithFractional.date(from: rawValue) {
            return parsed
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let parsed = formatter.date(from: rawValue) {
            return parsed
        }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return fallback.date(from: rawValue)
    }
}

private extension ReceiptStat {
    func toSupabasePayload(userId: UUID) throws -> [String: PostgREST.AnyJSON] {
        let encoder = ISO8601DateFormatter()
        let detailFieldsArray: [[String: Any]] = detailFields.map {
            [
                "id": $0.id.uuidString,
                "label": $0.label,
                "value": $0.value,
                "kind": $0.kind.rawValue
            ]
        }
        let lineItemsArray: [[String: Any]] = lineItems.map {
            var payload: [String: Any] = [
                "id": $0.id.uuidString,
                "title": $0.title
            ]
            payload["amount"] = $0.amount ?? NSNull()
            payload["quantity"] = $0.quantity ?? NSNull()
            return payload
        }

        return [
            "id": .string(id.uuidString),
            "user_id": .string(userId.uuidString),
            "source": .string(source.rawValue),
            "legacy_note_id": legacyNoteId.map { .string($0.uuidString) } ?? .null,
            "title": .string(title),
            "merchant": .string(merchant),
            "amount": .double(amount),
            "date": .string(encoder.string(from: date)),
            "transaction_time": transactionTime.map { .string(encoder.string(from: $0)) } ?? .null,
            "category": .string(category),
            "subtotal": subtotal.map(PostgREST.AnyJSON.double) ?? .null,
            "tax": tax.map(PostgREST.AnyJSON.double) ?? .null,
            "tip": tip.map(PostgREST.AnyJSON.double) ?? .null,
            "payment_method": paymentMethod.map(PostgREST.AnyJSON.string) ?? .null,
            "image_urls": .array(imageUrls.map { .string($0) }),
            "detail_fields": try ReceiptJSONEncoder.convertToAnyJSON(detailFieldsArray),
            "line_items": try ReceiptJSONEncoder.convertToAnyJSON(lineItemsArray),
            "year": year.map { .integer($0) } ?? .null,
            "month": month.map { .string($0) } ?? .null,
            "updated_at": .string(encoder.string(from: Date()))
        ]
    }
}

private enum ReceiptJSONEncoder {
    static func convertToAnyJSON(_ object: Any) throws -> PostgREST.AnyJSON {
        if let dict = object as? [String: Any] {
            var result: [String: PostgREST.AnyJSON] = [:]
            for (key, value) in dict {
                result[key] = try convertToAnyJSON(value)
            }
            return .object(result)
        }

        if let array = object as? [Any] {
            return .array(try array.map { try convertToAnyJSON($0) })
        }

        if let string = object as? String {
            return .string(string)
        }

        if let bool = object as? Bool {
            return .bool(bool)
        }

        if let number = object as? NSNumber {
            if CFNumberGetType(number as CFNumber) == .charType {
                return .bool(number.boolValue)
            }
            if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return .integer(number.intValue)
            }
            return .double(number.doubleValue)
        }

        if object is NSNull || "\(type(of: object))" == "Optional<Any>" {
            return .null
        }

        throw NSError(domain: "ReceiptJSONEncoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported receipt JSON type: \(type(of: object))"])
    }
}
