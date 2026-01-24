import SwiftUI

struct ReceiptStatsView: View {
    @StateObject private var notesManager = NotesManager.shared
    @State private var currentYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedNote: Note? = nil
    @State private var categoryBreakdown: YearlyCategoryBreakdown? = nil
    @State private var isLoadingCategories = false
    @State private var selectedCategory: String? = nil
    @State private var showRecurringExpenses = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var categoryBreakdownDebounceTask: Task<Void, Never>? = nil  // Debounce task for category recalculation
    @State private var contentHeight: CGFloat = 400

    var searchText: String? = nil

    var isPopup: Bool = false

    var availableYears: [Int] {
        notesManager.getAvailableReceiptYears()
    }

    var currentYearStats: YearlyReceiptSummary? {
        let stats = notesManager.getReceiptStatistics(year: currentYear).first
        // Apply search filter if searchText is provided
        if let searchText = searchText, !searchText.isEmpty {
            // Filter receipts by search text
            // This will be handled by filtering the underlying notes
            return stats
        }
        return stats
    }
    
    var filteredReceiptNotes: [Note] {
        let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })
        guard let receiptsFolderId = receiptsFolder?.id else { return [] }
        
        var receiptNotes = notesManager.notes.filter { note in
            guard let folderId = note.folderId else { return false }
            var currentFolderId: UUID? = folderId
            while let currentId = currentFolderId {
                if currentId == receiptsFolderId {
                    return true
                }
                currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
            }
            return false
        }
        
        // Apply search filter
        if let searchText = searchText, !searchText.isEmpty {
            receiptNotes = receiptNotes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return receiptNotes
    }

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: isPopup ? 8 : 12) {
                // Main card container
                VStack(alignment: .leading, spacing: 0) {
                    if showRecurringExpenses {
                        RecurringExpenseStatsContent(searchText: searchText)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        // Year selector header with total
                        HStack(spacing: 12) {
                        if !availableYears.isEmpty && currentYear != availableYears.min() {
                            Button(action: { selectPreviousYear() }) {
                                Image(systemName: "chevron.left")
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    .frame(width: 28, height: 28)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 28, height: 28)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%d", currentYear))
                                .font(FontManager.geist(size: 24, weight: .semibold))
                                .foregroundColor(.primary)

                            if let stats = currentYearStats {
                                Text(CurrencyParser.formatAmountNoDecimals(stats.yearlyTotal))
                                    .font(FontManager.geist(size: 17, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }

                        // Right arrow to navigate to next year
                        if !availableYears.isEmpty && currentYear != availableYears.max() {
                            Button(action: { selectNextYear() }) {
                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    .frame(width: 28, height: 28)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 28, height: 28)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                    // Category Breakdown Section
                    if isLoadingCategories {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.9, anchor: .center)

                            Text("Categorizing receipts...")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(.gray)

                            Spacer()
                        }
                        .padding(16)
                    } else if let breakdown = categoryBreakdown, !breakdown.categories.isEmpty {
                        HorizontalCategoryBreakdownView(
                            categoryBreakdown: breakdown,
                            onCategoryTap: { category in
                                selectedCategory = category
                            }
                        )
                    }


                    // Monthly breakdown
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) { // Reduced spacing from 32 to 16
                            if let stats = currentYearStats {
                                if stats.monthlySummaries.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(FontManager.geist(size: 32, weight: .light))
                                            .foregroundColor(.gray)

                                        Text("No receipts found")
                                            .font(FontManager.geist(size: .body, weight: .regular))
                                            .foregroundColor(.gray)

                                        Text("for this year")
                                            .font(FontManager.geist(size: .caption, weight: .regular))
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    ForEach(Array(stats.monthlySummaries.enumerated()), id: \.element.id) { index, monthlySummary in
                                        let categorizedReceiptsForMonth = getCategorizedReceiptsForMonth(monthlySummary.monthDate)

                                        MonthlySummaryReceiptCard(
                                            monthlySummary: monthlySummary,
                                            isLast: index == stats.monthlySummaries.count - 1,
                                            onReceiptTap: { noteId in
                                                selectedNote = notesManager.notes.first { $0.id == noteId }
                                            },
                                            categorizedReceipts: categorizedReceiptsForMonth
                                        )
                                        .padding(.horizontal, 12) // Match home page widget padding

                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(FontManager.geist(size: 32, weight: .light))
                                        .foregroundColor(.gray)

                                    Text("No receipts found")
                                        .font(FontManager.geist(size: .body, weight: .regular))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            // Set current year to the most recent year with data
            if !availableYears.isEmpty {
                currentYear = availableYears.first ?? Calendar.current.component(.year, from: Date())
            }
            // Load category breakdown for current year
            loadCategoryBreakdown()
        }
        .onChange(of: currentYear) { _ in
            // Reload category breakdown when year changes
            loadCategoryBreakdown()
        }
        .onChange(of: notesManager.notes.count) { _ in
            // OPTIMIZATION: Debounce category breakdown reload when notes change
            // Prevents recalculation on every note modification (e.g., during bulk import)
            // Uses 500ms debounce to batch multiple changes together
            categoryBreakdownDebounceTask?.cancel()
            categoryBreakdownDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if !Task.isCancelled {
                    loadCategoryBreakdown()
                }
            }
        }
        .sheet(item: $selectedNote) { note in
            NavigationView {
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { selectedNote != nil },
                    set: { if !$0 { selectedNote = nil } }
                ))
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedCategory != nil },
            set: { if !$0 { selectedCategory = nil } }
        )) {
            if let category = selectedCategory, let breakdown = categoryBreakdown {
                let categoryReceipts = breakdown.allReceipts.filter { $0.category == category }
                CategoryBreakdownModal(
                    monthlyReceipts: categoryReceipts,
                    monthName: "\(category) - \(currentYear)",
                    monthlyTotal: categoryReceipts.reduce(0) { $0 + $1.amount }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func selectPreviousYear() {
        if let previousYear = availableYears.first(where: { $0 < currentYear }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentYear = previousYear
            }
        }
    }

    private func selectNextYear() {
        if let nextYear = availableYears.first(where: { $0 > currentYear }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentYear = nextYear
            }
        }
    }

    private func loadCategoryBreakdown() {
        isLoadingCategories = true
        Task {
            let breakdown = await notesManager.getCategoryBreakdown(for: currentYear)
            await MainActor.run {
                categoryBreakdown = breakdown
                isLoadingCategories = false
            }
        }
    }

    private func getCategorizedReceiptsForMonth(_ monthDate: Date) -> [ReceiptStat] {
        guard let breakdown = categoryBreakdown else { return [] }

        let calendar = Calendar.current
        let month = calendar.component(.month, from: monthDate)
        let year = calendar.component(.year, from: monthDate)

        return breakdown.allReceipts.filter { receipt in
            let receiptMonth = calendar.component(.month, from: receipt.date)
            let receiptYear = calendar.component(.year, from: receipt.date)
            return receiptMonth == month && receiptYear == year
        }
    }

}

// MARK: - Recurring Expense Stats Content

struct RecurringExpenseStatsContent: View {
    @State private var recurringExpenses: [RecurringExpense] = []
    @State private var recurringInstances: [RecurringInstance] = []
    @State private var isLoading = true
    @State private var selectedExpense: RecurringExpense? = nil
    @State private var showEditSheet = false
    @State private var hasLoadedData = false
    @Environment(\.colorScheme) var colorScheme
    
    var searchText: String? = nil
    
    var filteredRecurringExpenses: [RecurringExpense] {
        guard let searchText = searchText, !searchText.isEmpty else {
            return recurringExpenses
        }
        return recurringExpenses.filter { expense in
            expense.title.localizedCaseInsensitiveContains(searchText) ||
            expense.category?.localizedCaseInsensitiveContains(searchText) ?? false ||
            expense.description?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    var monthlyTotal: Double {
        // Only count active expenses in the total
        filteredRecurringExpenses.filter { $0.isActive }.reduce(0) { total, expense in
            total + Double(truncating: expense.amount as NSDecimalNumber)
        }
    }

    var yearlyProjection: Double {
        monthlyTotal * 12
    }

    var activeCount: Int {
        filteredRecurringExpenses.filter { $0.isActive }.count
    }

    // Sort expenses by next occurrence date (soonest first)
    var sortedExpenses: [RecurringExpense] {
        filteredRecurringExpenses.sorted { $0.nextOccurrence < $1.nextOccurrence }
    }

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .padding(.vertical, 16)
            } else if filteredRecurringExpenses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "repeat.circle.dashed")
                        .font(FontManager.geist(size: 32, weight: .light))
                        .foregroundColor(.gray)

                    Text("No recurring expenses")
                        .font(FontManager.geist(size: .body, weight: .regular))
                        .foregroundColor(.gray)

                    Text("Create one using the repeat icon in notes")
                        .font(FontManager.geist(size: .caption, weight: .regular))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Stats
                HStack(spacing: 12) {
                    StatBox(
                        label: "Monthly",
                        value: CurrencyParser.formatAmountNoDecimals(monthlyTotal),
                        icon: "calendar",
                        valueColor: .green,
                        isBold: true
                    )

                    StatBox(
                        label: "Yearly",
                        value: CurrencyParser.formatAmountNoDecimals(yearlyProjection),
                        icon: "chart.line.uptrend.xyaxis",
                        valueColor: .green,
                        isBold: true
                    )

                    StatBox(
                        label: "Active",
                        value: "\(activeCount)",
                        icon: "repeat",
                        valueColor: nil,
                        isBold: true
                    )
                }
                .padding(.top, -4)
                .padding(.bottom, 4)

                // Recurring expenses list (sorted by next occurrence date)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(sortedExpenses) { expense in
                            Menu {
                                Button(action: {
                                    selectedExpense = expense
                                    // Add small delay to ensure state is updated before sheet shows
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                        showEditSheet = true
                                    }
                                }) {
                                    Label("Edit Recurring", systemImage: "pencil")
                                }

                                Button(action: {
                                    Task {
                                        try? await RecurringExpenseService.shared.toggleRecurringExpenseActive(id: expense.id, isActive: !expense.isActive)
                                        // Refresh the list
                                        await MainActor.run {
                                            refreshRecurringExpenses()
                                        }
                                    }
                                }) {
                                    Label(expense.isActive ? "Pause" : "Resume", systemImage: expense.isActive ? "pause.circle" : "play.circle")
                                }

                                Button(role: .destructive, action: {
                                    Task {
                                        try? await RecurringExpenseService.shared.deleteRecurringExpense(id: expense.id)
                                        // Refresh the list
                                        await MainActor.run {
                                            refreshRecurringExpenses()
                                        }
                                    }
                                }) {
                                    Label("Delete Recurring", systemImage: "trash")
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(expense.title)
                                            .font(.subheadline)
                                            .fontWeight(.regular)
                                        HStack(spacing: 8) {
                                            // Show next occurrence date
                                            Image(systemName: "calendar")
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(.secondary)
                                            Text(formatInstanceDate(expense.nextOccurrence))
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            // Show frequency
                                            Text("• \(expense.frequency.displayName)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(expense.formattedAmount)
                                            .font(.subheadline)
                                            .fontWeight(.regular)
                                        Text(expense.formattedYearlyAmount)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.05))
                                .cornerRadius(8)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .sheet(isPresented: $showEditSheet, onDismiss: {
            selectedExpense = nil
            // Refresh the list when sheet closes (in case data was edited)
            refreshRecurringExpenses()
        }) {
            if let expense = selectedExpense {
                RecurringExpenseEditView(expense: expense, isPresented: $showEditSheet)
                    .presentationBg()
            } else {
                // Fallback loading state if data isn't ready yet
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(colorScheme == .dark ? Color.white : Color.black)

                    Text("Loading expense details...")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            }
        }
        .onAppear {
            // Only load if we haven't already loaded
            if !hasLoadedData {
                loadRecurringExpenses()
            }
        }
    }

    private func loadRecurringExpenses() {
        isLoading = true
        Task {
            do {
                // Fetch all expenses (both active and paused)
                let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()

                await MainActor.run {
                    // Sort expenses by upcoming due date (soonest first)
                    recurringExpenses = expenses.sorted { $0.nextOccurrence < $1.nextOccurrence }
                    isLoading = false
                    hasLoadedData = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("❌ Error loading recurring expenses: \(error.localizedDescription)")
            }
        }
    }

    /// Manual refresh - reload data even if already loaded
    private func refreshRecurringExpenses() {
        hasLoadedData = false
        loadRecurringExpenses()
    }

    /// Format instance date in readable way
    private func formatInstanceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        let components = calendar.dateComponents([.day], from: today, to: targetDate)
        let daysFromNow = components.day ?? 0

        if daysFromNow == 0 {
            return "Today"
        } else if daysFromNow == 1 {
            return "Tomorrow"
        } else if daysFromNow > 1 && daysFromNow <= 7 {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    /// Format upcoming date in a readable way
    private func formatUpcomingDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        let components = calendar.dateComponents([.day], from: today, to: targetDate)
        let daysFromNow = components.day ?? 0

        if daysFromNow == 0 {
            return "Today"
        } else if daysFromNow == 1 {
            return "Tomorrow"
        } else if daysFromNow > 1 && daysFromNow <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    /// Calculate yearly total for an expense based on its frequency
    private func getYearlyTotal(for expense: RecurringExpense) -> String {
        let amountDouble = Double(truncating: expense.amount as NSDecimalNumber)
        let yearlyAmount: Double

        switch expense.frequency {
        case .daily:
            yearlyAmount = amountDouble * 365
        case .weekly:
            yearlyAmount = amountDouble * 52
        case .biweekly:
            yearlyAmount = amountDouble * 26
        case .monthly:
            yearlyAmount = amountDouble * 12
        case .yearly:
            yearlyAmount = amountDouble
        case .custom:
            // For custom frequency, assume weekly as a reasonable default
            // TODO: Add customRecurrenceDays to RecurringExpense model for accurate calculation
            yearlyAmount = amountDouble * 52
        }

        return CurrencyParser.formatAmountNoDecimals(yearlyAmount)
    }

}

struct StatBox: View {
    let label: String
    let value: String
    let icon: String
    let valueColor: Color?
    let isBold: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.headline)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(valueColor ?? .primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor(white: 0.98, alpha: 1)))
        .cornerRadius(8)
    }
}

#Preview {
    ReceiptStatsView()
}
