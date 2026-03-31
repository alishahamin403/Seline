import Foundation

enum ReceiptSource: String, Codable, Hashable {
    case native
    case migratedLegacy
    case legacyFallback
}

enum ReceiptFieldKind: String, Codable, Hashable {
    case text
    case currency
    case date
    case time
    case datetime
}

struct ReceiptField: Identifiable, Hashable, Codable {
    let id: UUID
    let label: String
    let value: String
    let kind: ReceiptFieldKind

    init(id: UUID = UUID(), label: String, value: String, kind: ReceiptFieldKind = .text) {
        self.id = id
        self.label = label
        self.value = value
        self.kind = kind
    }
}

struct ReceiptLineItem: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let amount: Double?
    let quantity: Double?

    init(id: UUID = UUID(), title: String, amount: Double? = nil, quantity: Double? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.quantity = quantity
    }
}

struct ReceiptDraft: Hashable, Codable {
    var merchant: String
    var total: Double
    var transactionDate: Date
    var transactionTime: Date?
    var category: String
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var paymentMethod: String?
    var detailFields: [ReceiptField]
    var lineItems: [ReceiptLineItem]
    var imageUrls: [String]

    init(
        merchant: String = "",
        total: Double = 0,
        transactionDate: Date = Date(),
        transactionTime: Date? = nil,
        category: String = "Other",
        subtotal: Double? = nil,
        tax: Double? = nil,
        tip: Double? = nil,
        paymentMethod: String? = nil,
        detailFields: [ReceiptField] = [],
        lineItems: [ReceiptLineItem] = [],
        imageUrls: [String] = []
    ) {
        self.merchant = merchant
        self.total = total
        self.transactionDate = transactionDate
        self.transactionTime = transactionTime
        self.category = category
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.paymentMethod = paymentMethod
        self.detailFields = detailFields
        self.lineItems = lineItems
        self.imageUrls = imageUrls
    }

    var resolvedMerchant: String {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Receipt" : trimmed
    }

    var resolvedTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return "\(resolvedMerchant) - \(formatter.string(from: transactionDate))"
    }
}

// MARK: - Receipt Statistics Models

struct ReceiptStat: Identifiable, Hashable, Codable {
    let id: UUID
    let source: ReceiptSource
    let title: String
    let merchant: String
    let amount: Double
    let date: Date
    let transactionTime: Date?
    let noteId: UUID
    let legacyNoteId: UUID?
    let year: Int?
    let month: String?
    var category: String
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let paymentMethod: String?
    let imageUrls: [String]
    let detailFields: [ReceiptField]
    let lineItems: [ReceiptLineItem]

    init(
        id: UUID = UUID(),
        source: ReceiptSource = .native,
        title: String,
        merchant: String? = nil,
        amount: Double,
        date: Date,
        transactionTime: Date? = nil,
        noteId: UUID,
        legacyNoteId: UUID? = nil,
        year: Int? = nil,
        month: String? = nil,
        category: String = "Other",
        subtotal: Double? = nil,
        tax: Double? = nil,
        tip: Double? = nil,
        paymentMethod: String? = nil,
        imageUrls: [String] = [],
        detailFields: [ReceiptField] = [],
        lineItems: [ReceiptLineItem] = []
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? ReceiptStat.extractMerchantName(from: title)
        self.amount = amount
        self.date = date
        self.transactionTime = transactionTime
        self.noteId = noteId
        self.legacyNoteId = legacyNoteId
        self.year = year
        self.month = month
        self.category = category
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.paymentMethod = paymentMethod
        self.imageUrls = imageUrls
        self.detailFields = detailFields
        self.lineItems = lineItems
    }

    init(from note: Note, year: Int? = nil, month: String? = nil, date: Date? = nil, category: String = "Other") {
        let effectiveDate = date ?? note.dateModified
        let amountSource = [note.title, note.content]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        self.init(
            id: note.id,
            source: .legacyFallback,
            title: note.title,
            merchant: ReceiptStat.extractMerchantName(from: note.title),
            amount: CurrencyParser.extractAmount(from: amountSource),
            date: effectiveDate,
            transactionTime: nil,
            noteId: note.id,
            legacyNoteId: note.id,
            year: year,
            month: month,
            category: category,
            subtotal: nil,
            tax: nil,
            tip: nil,
            paymentMethod: nil,
            imageUrls: note.imageUrls,
            detailFields: [],
            lineItems: []
        )
    }

    var canonicalReceiptId: UUID {
        id
    }

    var searchableText: String {
        let detailText = detailFields
            .map { "\($0.label) \($0.value)" }
            .joined(separator: " ")
        let lineItemText = lineItems
            .map { item in
                let amountText = item.amount.map { CurrencyParser.formatAmount($0) } ?? ""
                return "\(item.title) \(amountText)"
            }
            .joined(separator: " ")

        return [
            title,
            merchant,
            category,
            CurrencyParser.formatAmount(amount),
            FormatterCache.shortDate.string(from: date),
            transactionTime.map { FormatterCache.shortTime.string(from: $0) } ?? "",
            paymentMethod ?? "",
            detailText,
            lineItemText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    static func extractMerchantName(from title: String) -> String {
        title
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DailyReceiptSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let day: Int
    let dayDate: Date
    let receipts: [ReceiptStat]

    var dailyTotal: Double {
        receipts.reduce(0) { $0 + $1.amount }
    }

    init(day: Int, dayDate: Date, receipts: [ReceiptStat]) {
        self.id = UUID()
        self.day = day
        self.dayDate = dayDate
        self.receipts = receipts.sorted { $0.date > $1.date }
    }

    var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: dayDate)
    }
}

struct MonthlyReceiptSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let month: String
    let monthDate: Date
    let dailySummaries: [DailyReceiptSummary]

    var monthlyTotal: Double {
        dailySummaries.reduce(0) { $0 + $1.dailyTotal }
    }

    var receipts: [ReceiptStat] {
        dailySummaries.flatMap { $0.receipts }
    }

    init(month: String, monthDate: Date, receipts: [ReceiptStat]) {
        self.id = UUID()
        self.month = month
        self.monthDate = monthDate

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: receipts) { receipt in
            calendar.startOfDay(for: receipt.date)
        }

        self.dailySummaries = grouped
            .map { dayDate, dayReceipts in
                DailyReceiptSummary(
                    day: calendar.component(.day, from: dayDate),
                    dayDate: dayDate,
                    receipts: dayReceipts
                )
            }
            .sorted { $0.dayDate > $1.dayDate }
    }
}

struct YearlyReceiptSummary: Identifiable, Codable, Hashable {
    let id: UUID
    let year: Int
    let monthlySummaries: [MonthlyReceiptSummary]

    var yearlyTotal: Double {
        monthlySummaries.reduce(0) { $0 + $1.monthlyTotal }
    }

    var yearString: String {
        String(year)
    }

    init(year: Int, monthlySummaries: [MonthlyReceiptSummary]) {
        self.id = UUID()
        self.year = year
        self.monthlySummaries = monthlySummaries.sorted { $0.monthDate > $1.monthDate }
    }
}

// MARK: - Category Statistics Models

struct CategoryStat: Identifiable, Hashable {
    let id: UUID
    let category: String
    let total: Double
    let count: Int

    var percentage: Double {
        0.0
    }

    init(category: String, total: Double = 0, count: Int = 0) {
        self.id = UUID()
        self.category = category
        self.total = total
        self.count = count
    }
}

struct YearlyCategoryBreakdown: Identifiable {
    let id: UUID
    let year: Int
    let categories: [CategoryStat]
    let yearlyTotal: Double
    let categoryReceipts: [String: [ReceiptStat]]
    let allReceipts: [ReceiptStat]

    var sortedCategories: [CategoryStatWithPercentage] {
        categories
            .map { stat in
                let receipts = categoryReceipts[stat.category] ?? []
                return CategoryStatWithPercentage(
                    category: stat.category,
                    total: stat.total,
                    count: stat.count,
                    percentage: yearlyTotal > 0 ? (stat.total / yearlyTotal) * 100 : 0,
                    receipts: receipts.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.total > $1.total }
    }

    init(year: Int, categories: [CategoryStat], yearlyTotal: Double, categoryReceipts: [String: [ReceiptStat]] = [:], allReceipts: [ReceiptStat] = []) {
        self.id = UUID()
        self.year = year
        self.categories = categories
        self.yearlyTotal = yearlyTotal
        self.categoryReceipts = categoryReceipts
        self.allReceipts = allReceipts
    }
}

struct CategoryStatWithPercentage: Identifiable {
    let id: UUID = UUID()
    let category: String
    let total: Double
    let count: Int
    let percentage: Double
    let receipts: [ReceiptStat]

    var formattedAmount: String {
        CurrencyParser.formatAmount(total)
    }

    var formattedPercentage: String {
        String(format: "%.1f%%", percentage)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
