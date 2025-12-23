import SwiftUI

struct ReceiptsDashboard: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var recurringExpenses: [RecurringExpense] = []
    @State private var isLoading = true
    @State private var selectedRecurringExpense: RecurringExpense?
    @State private var showingEditForm = false
    @State private var showingDeleteConfirmation = false
    @State private var expenseToDelete: RecurringExpense?

    var activeRecurringExpenses: [RecurringExpense] {
        recurringExpenses.filter { $0.isActive }
    }

    var monthlyRecurringTotal: Double {
        activeRecurringExpenses.reduce(0) { total, expense in
            total + Double(truncating: expense.amount as NSDecimalNumber)
        }
    }

    var yearlyRecurringTotal: Double {
        monthlyRecurringTotal * 12
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats Section
                    ReceiptsStatsView(
                        monthlyRecurringTotal: monthlyRecurringTotal,
                        yearlyRecurringTotal: yearlyRecurringTotal,
                        recurringExpenseCount: activeRecurringExpenses.count
                    )

                    if !activeRecurringExpenses.isEmpty {
                        // Recurring Expenses Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Active Recurring Expenses")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))
                                Spacer()
                                Text("\(activeRecurringExpenses.count)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                            VStack(spacing: 12) {
                                ForEach(activeRecurringExpenses) { expense in
                                    RecurringExpenseRow(
                                        expense: expense,
                                        onEdit: {
                                            selectedRecurringExpense = expense
                                            showingEditForm = true
                                        },
                                        onDelete: {
                                            expenseToDelete = expense
                                            showingDeleteConfirmation = true
                                        },
                                        onToggle: {
                                            toggleExpenseActive(expense)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        }
                        .shadcnTileStyle(colorScheme: colorScheme)
                        .padding(.horizontal, 12)
                    }

                    // Empty State
                    if recurringExpenses.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "repeat.circle.dashed")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                            Text("No Recurring Expenses")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            Text("Create your first recurring expense using the repeat icon")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    }

                    Spacer()
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Receipts & Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadRecurringExpenses()
            }
            .sheet(isPresented: $showingEditForm) {
                if let expense = selectedRecurringExpense {
                    EditRecurringExpenseForm(
                        expense: expense,
                        onSave: { updatedExpense in
                            updateRecurringExpense(updatedExpense)
                        }
                    )
                }
            }
            .alert("Delete Recurring Expense?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let expense = expenseToDelete {
                        deleteRecurringExpense(expense)
                    }
                }
            } message: {
                Text("This will remove '\(expenseToDelete?.title ?? "")' from your recurring expenses.")
            }
        }
    }

    private func loadRecurringExpenses() {
        isLoading = true
        Task {
            do {
                let expenses = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
                await MainActor.run {
                    recurringExpenses = expenses
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

    private func toggleExpenseActive(_ expense: RecurringExpense) {
        Task {
            do {
                try await RecurringExpenseService.shared.toggleRecurringExpenseActive(
                    id: expense.id,
                    isActive: !expense.isActive
                )
                await MainActor.run {
                    if let index = recurringExpenses.firstIndex(where: { $0.id == expense.id }) {
                        recurringExpenses[index].isActive.toggle()
                    }
                }
            } catch {
                print("❌ Error toggling expense: \(error.localizedDescription)")
            }
        }
    }

    private func updateRecurringExpense(_ expense: RecurringExpense) {
        Task {
            do {
                let updated = try await RecurringExpenseService.shared.updateRecurringExpense(expense)
                await MainActor.run {
                    if let index = recurringExpenses.firstIndex(where: { $0.id == expense.id }) {
                        recurringExpenses[index] = updated
                    }
                    selectedRecurringExpense = nil
                    showingEditForm = false
                }
            } catch {
                print("❌ Error updating expense: \(error.localizedDescription)")
            }
        }
    }

    private func deleteRecurringExpense(_ expense: RecurringExpense) {
        Task {
            do {
                try await RecurringExpenseService.shared.deleteRecurringExpense(id: expense.id)
                await MainActor.run {
                    recurringExpenses.removeAll { $0.id == expense.id }
                    expenseToDelete = nil
                    showingDeleteConfirmation = false
                }
            } catch {
                print("❌ Error deleting expense: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Stats View

struct ReceiptsStatsView: View {
    @Environment(\.colorScheme) var colorScheme

    let monthlyRecurringTotal: Double
    let yearlyRecurringTotal: Double
    let recurringExpenseCount: Int

    var body: some View {
        VStack(spacing: 12) {
            // Monthly Total
            StatCard(
                title: "Monthly Recurring",
                value: CurrencyParser.formatAmountNoDecimals(monthlyRecurringTotal),
                icon: "calendar.circle.fill",
                backgroundColor: Color.blue.opacity(0.1)
            )

            // Yearly Projection
            StatCard(
                title: "Yearly Projection",
                value: CurrencyParser.formatAmount(yearlyRecurringTotal),
                icon: "chart.line.uptrend.xyaxis.circle.fill",
                backgroundColor: Color.green.opacity(0.1)
            )

            // Active Count
            StatCard(
                title: "Active Recurring",
                value: "\(recurringExpenseCount)",
                icon: "repeat.circle.fill",
                backgroundColor: Color.orange.opacity(0.1)
            )
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .padding(.horizontal, 12)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let backgroundColor: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
            }

            Spacer()
        }
        .padding(12)
        .background(Color.shadcnTileBackground(colorScheme))
        .cornerRadius(ShadcnRadius.xl)
    }
}

// MARK: - Recurring Expense Row

struct RecurringExpenseRow: View {
    @Environment(\.colorScheme) var colorScheme

    let expense: RecurringExpense
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        Text(formatDate(expense.nextOccurrence))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        Text("•")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        Text(expense.frequency.displayName)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        Text("•")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        Text(expense.statusBadge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(expense.isActive ? .green : .orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(expense.formattedAmount)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                    Text(expense.formattedYearlyAmount)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                        Text("Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: expense.isActive ? "pause" : "play.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(expense.isActive ? "Pause" : "Resume")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("Delete")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(Color.shadcnTileBackground(colorScheme))
        .cornerRadius(ShadcnRadius.xl)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Edit Form (Placeholder)

struct EditRecurringExpenseForm: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    let expense: RecurringExpense
    let onSave: (RecurringExpense) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Text(expense.title)
                    Text(expense.formattedAmount)
                    Text(expense.frequency.displayName)
                }

                Section {
                    Button("Save Changes") {
                        onSave(expense)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
            .navigationTitle("Edit Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ReceiptsDashboard()
}
