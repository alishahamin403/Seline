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

    var isPopup: Bool = false

    var availableYears: [Int] {
        notesManager.getAvailableReceiptYears()
    }

    var currentYearStats: YearlyReceiptSummary? {
        notesManager.getReceiptStatistics(year: currentYear).first
    }

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: isPopup ? 8 : 12) {
                // Close button for popup mode
                if isPopup {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }

                // Toggle between Receipts and Recurring Expenses - EmailTabView style
                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRecurringExpenses = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "receipt.fill")
                                .font(.system(size: 14, weight: .medium))

                            Text("Receipts")
                                .font(.system(size: 14, weight: !showRecurringExpenses ? .semibold : .medium))
                        }
                        .foregroundColor(
                            !showRecurringExpenses ? .white : .gray
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(!showRecurringExpenses ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRecurringExpenses = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "repeat.circle.fill")
                                .font(.system(size: 14, weight: .medium))

                            Text("Recurring")
                                .font(.system(size: 14, weight: showRecurringExpenses ? .semibold : .medium))
                        }
                        .foregroundColor(
                            showRecurringExpenses ? .white : .gray
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showRecurringExpenses ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.gray.opacity(0.08))
                )
                .padding(.horizontal, 12)

                // Main card container
                VStack(alignment: .leading, spacing: 0) {
                    if showRecurringExpenses {
                        RecurringExpenseStatsContent()
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        // Year selector header with total
                        HStack(spacing: 12) {
                        if !availableYears.isEmpty && currentYear != availableYears.min() {
                            Button(action: { selectPreviousYear() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 32, height: 32)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 32, height: 32)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%d", currentYear))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)

                            if let stats = currentYearStats {
                                Text(CurrencyParser.formatAmount(stats.yearlyTotal))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }

                        Spacer()

                        if !availableYears.isEmpty && currentYear != availableYears.max() {
                            Button(action: { selectNextYear() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 32, height: 32)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(16)

                    // Category Breakdown Section
                    if isLoadingCategories {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.9, anchor: .center)

                            Text("Categorizing receipts...")
                                .font(.system(size: 14, weight: .regular))
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
                        VStack(spacing: 0) {
                            if let stats = currentYearStats {
                                if stats.monthlySummaries.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32, weight: .light))
                                            .foregroundColor(.gray)

                                        Text("No receipts found")
                                            .font(.system(.body, design: .default))
                                            .foregroundColor(.gray)

                                        Text("for this year")
                                            .font(.system(.caption, design: .default))
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

                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundColor(.gray)

                                    Text("No receipts found")
                                        .font(.system(.body, design: .default))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
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
            // Reload category breakdown when notes are added/removed
            loadCategoryBreakdown()
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
    @State private var isLoading = true
    @State private var selectedExpense: RecurringExpense? = nil
    @State private var showEditSheet = false
    @Environment(\.colorScheme) var colorScheme

    var monthlyTotal: Double {
        // Only count active expenses in the total
        recurringExpenses.filter { $0.isActive }.reduce(0) { total, expense in
            total + Double(truncating: expense.amount as NSDecimalNumber)
        }
    }

    var yearlyProjection: Double {
        monthlyTotal * 12
    }

    var activeCount: Int {
        recurringExpenses.filter { $0.isActive }.count
    }

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .padding(.vertical, 16)
            } else if recurringExpenses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "repeat.circle.dashed")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.gray)

                    Text("No recurring expenses")
                        .font(.system(.body, design: .default))
                        .foregroundColor(.gray)

                    Text("Create one using the repeat icon in notes")
                        .font(.system(.caption, design: .default))
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
                        valueColor: .green
                    )

                    StatBox(
                        label: "Yearly",
                        value: CurrencyParser.formatAmountNoDecimals(yearlyProjection),
                        icon: "chart.line.uptrend.xyaxis",
                        valueColor: .green
                    )

                    StatBox(
                        label: "Active",
                        value: "\(activeCount)",
                        icon: "repeat",
                        valueColor: nil
                    )
                }
                .padding(.vertical, 8)

                // Recurring expenses list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(recurringExpenses) { expense in
                            Menu {
                                Button(action: {
                                    selectedExpense = expense
                                    showEditSheet = true
                                }) {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button(action: {
                                    Task {
                                        try? await RecurringExpenseService.shared.toggleRecurringExpenseActive(id: expense.id, isActive: !expense.isActive)
                                        // Reload the list
                                        await MainActor.run {
                                            loadRecurringExpenses()
                                        }
                                    }
                                }) {
                                    Label(expense.isActive ? "Pause" : "Resume", systemImage: expense.isActive ? "pause.circle" : "play.circle")
                                }

                                Button(role: .destructive, action: {
                                    Task {
                                        try? await RecurringExpenseService.shared.deleteRecurringExpense(id: expense.id)
                                        // Reload the list
                                        await MainActor.run {
                                            loadRecurringExpenses()
                                        }
                                    }
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(expense.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        HStack(spacing: 8) {
                                            Text(expense.frequency.displayName)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let category = expense.category {
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text(category)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(expense.formattedAmount)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        if !expense.isActive {
                                            Text("Paused")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
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
            // Reload the list when sheet closes
            loadRecurringExpenses()
        }) {
            if let expense = selectedExpense {
                RecurringExpenseEditView(expense: expense, isPresented: $showEditSheet)
                    .presentationBg()
            }
        }
        .onAppear {
            loadRecurringExpenses()
        }
    }

    private func loadRecurringExpenses() {
        isLoading = true
        Task {
            do {
                // Fetch all expenses (both active and paused)
                let expenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
                await MainActor.run {
                    // Sort by most recent first
                    recurringExpenses = expenses.sorted { $0.createdAt > $1.createdAt }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("❌ Error loading recurring expenses: \(error.localizedDescription)")
            }
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let icon: String
    let valueColor: Color?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text(value)
                .font(.headline)
                .fontWeight(.regular)
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
