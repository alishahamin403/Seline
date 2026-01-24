import Foundation

@MainActor
class ExpenseBudgetService: ObservableObject {
    static let shared = ExpenseBudgetService()

    @Published private(set) var budgets: [ExpenseBudget] = []

    private let storageKey = "expenseBudgets"
    private let notesManager = NotesManager.shared

    private init() {
        loadBudgets()
    }

    // MARK: - CRUD

    func upsertBudget(
        name: String,
        limit: Double,
        period: ExpenseBudgetPeriod
    ) -> ExpenseBudget {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingIndex = budgets.firstIndex(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            var updated = budgets[existingIndex]
            updated.limit = limit
            updated.period = period
            updated.updatedAt = Date()
            budgets[existingIndex] = updated
            saveBudgets()
            return updated
        }

        let newBudget = ExpenseBudget(name: trimmedName, limit: limit, period: period)
        budgets.insert(newBudget, at: 0)
        saveBudgets()
        return newBudget
    }

    func deleteBudget(id: UUID) {
        budgets.removeAll { $0.id == id }
        saveBudgets()
    }

    func budget(for name: String) -> ExpenseBudget? {
        budgets.first { $0.name.lowercased() == name.lowercased() && $0.isActive }
    }

    // MARK: - Status

    func status(for budget: ExpenseBudget) -> ExpenseBudgetStatus {
        let spent = currentSpend(for: budget)
        let limit = max(budget.limit, 0.01)
        let progress = min(spent / limit, 1.0)
        return ExpenseBudgetStatus(spent: spent, limit: budget.limit, progress: progress)
    }

    func currentSpend(for budget: ExpenseBudget) -> Double {
        let receipts = receiptsForCurrentPeriod(period: budget.period)
        let matching = receipts.filter { matchesExpense($0, name: budget.name) }
        return matching.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Storage

    private func loadBudgets() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            budgets = []
            return
        }
        do {
            budgets = try JSONDecoder().decode([ExpenseBudget].self, from: data)
        } catch {
            budgets = []
        }
    }

    private func saveBudgets() {
        do {
            let data = try JSONEncoder().encode(budgets)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ Failed to save expense budgets: \(error)")
        }
    }

    // MARK: - Receipt Matching

    private func receiptsForCurrentPeriod(period: ExpenseBudgetPeriod) -> [ReceiptStat] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let yearStats = notesManager.getReceiptStatistics(year: currentYear)
        guard let stats = yearStats.first else { return [] }

        switch period {
        case .monthly:
            let month = calendar.component(.month, from: Date())
            if let summary = stats.monthlySummaries.first(where: { calendar.component(.month, from: $0.monthDate) == month }) {
                return summary.receipts
            }
            return []
        case .weekly:
            let receipts = stats.monthlySummaries.flatMap { $0.receipts }
            let currentWeek = calendar.component(.weekOfYear, from: Date())
            let currentWeekYear = calendar.component(.yearForWeekOfYear, from: Date())
            return receipts.filter { receipt in
                let receiptWeek = calendar.component(.weekOfYear, from: receipt.date)
                let receiptWeekYear = calendar.component(.yearForWeekOfYear, from: receipt.date)
                return receiptWeek == currentWeek && receiptWeekYear == currentWeekYear
            }
        }
    }

    private func matchesExpense(_ receipt: ReceiptStat, name: String) -> Bool {
        let needle = name.lowercased()
        let haystack = "\(receipt.title) \(receipt.category)".lowercased()

        if haystack.contains(needle) {
            return true
        }

        let tokens = needle
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count > 2 }

        return tokens.contains { haystack.contains($0) }
    }
}
