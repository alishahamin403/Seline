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
                                Label("Active Recurring Expenses", systemImage: "repeat.circle.fill")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(activeRecurringExpenses.count)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            VStack(spacing: 8) {
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
                            .padding(.horizontal, 16)
                        }
                    }

                    // Empty State
                    if recurringExpenses.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "repeat.circle.dashed")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("No Recurring Expenses")
                                .font(.headline)
                            Text("Create your first recurring expense using the repeat icon")
                                .font(.subheadline)
                                .foregroundColor(.gray)
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
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let backgroundColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(8)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Text(expense.frequency.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(expense.statusBadge)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(expense.isActive ? .green : .orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(expense.formattedAmount)
                        .font(.headline)
                        .fontWeight(.bold)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(expense.formattedYearlyAmount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("yearly")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Divider
            Divider()

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.circle.fill")
                        Text("Edit")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Spacer()

                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: expense.isActive ? "pause.circle.fill" : "play.circle.fill")
                        Text(expense.isActive ? "Pause" : "Resume")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }

                Spacer()

                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.circle.fill")
                        Text("Delete")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        )
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
