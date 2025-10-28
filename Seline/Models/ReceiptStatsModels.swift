import Foundation

// MARK: - Receipt Statistics Models

// Note: This file should be in the same module as NoteModels.swift
// The Note struct is defined in NoteModels.swift

/// Represents a single receipt with parsed amount
struct ReceiptStat: Identifiable, Hashable {
    let id: UUID
    let title: String
    let amount: Double
    let date: Date
    let noteId: UUID
    let year: Int?
    let month: String?

    init(id: UUID = UUID(), title: String, amount: Double, date: Date, noteId: UUID, year: Int? = nil, month: String? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.noteId = noteId
        self.year = year
        self.month = month
    }

    init(from note: Note, year: Int? = nil, month: String? = nil) {
        self.id = UUID()
        self.title = note.title
        // Extract amount from note content (body text), fallback to title if content is empty
        self.amount = CurrencyParser.extractAmount(from: note.content.isEmpty ? note.title : note.content)
        self.date = note.dateModified
        self.noteId = note.id
        self.year = year
        self.month = month
    }
}

/// Represents all receipts for a specific day
struct DailyReceiptSummary: Identifiable {
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

/// Represents all receipts for a specific month
struct MonthlyReceiptSummary: Identifiable {
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

        // Group receipts by day
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: receipts) { receipt in
            calendar.startOfDay(for: receipt.date)
        }

        // Create DailyReceiptSummary for each day, sorted by date (newest first)
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

/// Represents all receipts for a specific year
struct YearlyReceiptSummary: Identifiable {
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
        // Sort months in reverse chronological order (December to January)
        self.monthlySummaries = monthlySummaries.sorted { $0.monthDate > $1.monthDate }
    }
}
