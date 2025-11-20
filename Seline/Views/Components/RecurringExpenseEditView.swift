import SwiftUI

struct RecurringExpenseEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var title: String
    @State private var description: String
    @State private var amount: String
    @State private var category: String
    @State private var selectedFrequency: RecurrenceFrequency
    @State private var selectedReminder: ReminderOption
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var expense: RecurringExpense
    @Binding var isPresented: Bool

    init(expense: RecurringExpense, isPresented: Binding<Bool>) {
        self.expense = expense
        self._isPresented = isPresented

        _title = State(initialValue: expense.title)
        _description = State(initialValue: expense.description ?? "")
        _amount = State(initialValue: String(format: "%.2f", Double(truncating: expense.amount as NSDecimalNumber)))
        _category = State(initialValue: expense.category ?? "")
        _selectedFrequency = State(initialValue: expense.frequency)
        _selectedReminder = State(initialValue: expense.reminderOption)
    }

    var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
            !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
            Double(amount) != nil &&
            Double(amount) ?? 0 > 0
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            }

            Button(action: saveChanges) {
                Text(isSaving ? "Saving..." : "Save Changes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFormValid && !isSaving ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isFormValid && !isSaving ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray.opacity(0.3))
                    )
            }
            .disabled(!isFormValid || isSaving)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Title", systemImage: "pencil.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            TextField("e.g., Netflix Subscription", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description (Optional)", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            TextField("Add notes...", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Amount
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Amount", systemImage: "dollarsign.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack {
                                Text("$")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                TextField("0.00", text: $amount)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Category
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Category (Optional)", systemImage: "tag.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            TextField("e.g., Entertainment", text: $category)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Frequency
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Recurrence Frequency", systemImage: "repeat.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Picker("Frequency", selection: $selectedFrequency) {
                                Text("Weekly").tag(RecurrenceFrequency.weekly)
                                Text("Bi-weekly").tag(RecurrenceFrequency.biweekly)
                                Text("Monthly").tag(RecurrenceFrequency.monthly)
                                Text("Yearly").tag(RecurrenceFrequency.yearly)
                            }
                            .pickerStyle(.segmented)
                        }

                        // Reminder Option
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Reminder", systemImage: "bell.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Picker("Reminder", selection: $selectedReminder) {
                                ForEach(ReminderOption.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer()

                        // Error Message
                        if showError {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .lineLimit(3)
                                Spacer()
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }

                    }
                    .padding(16)
                }

                Divider()
                    .padding(.top, 16)

                actionButtonsSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("Edit Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }

    private func saveChanges() {
        guard isFormValid else {
            errorMessage = "Please fill in all required fields"
            showError = true
            return
        }

        guard let amountDouble = Double(amount), amountDouble > 0 else {
            errorMessage = "Please enter a valid amount"
            showError = true
            return
        }

        isSaving = true

        Task {
            do {
                // Update recurring expense
                var updatedExpense = expense
                updatedExpense.title = title.trimmingCharacters(in: .whitespaces)
                updatedExpense.description = description.isEmpty ? nil : description
                updatedExpense.amount = Decimal(amountDouble)
                updatedExpense.category = category.isEmpty ? nil : category
                updatedExpense.frequency = selectedFrequency
                updatedExpense.reminderOption = selectedReminder
                updatedExpense.updatedAt = Date()

                try await RecurringExpenseService.shared.updateRecurringExpense(updatedExpense)

                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
                print("❌ Error saving changes: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    RecurringExpenseEditView(
        expense: RecurringExpense(
            id: UUID(),
            userId: "test-user",
            title: "Netflix",
            description: "Streaming service",
            amount: 15.99,
            category: "Entertainment",
            frequency: .monthly,
            startDate: Date(),
            endDate: nil,
            nextOccurrence: Date().addingTimeInterval(86400 * 30),
            reminderOption: .threeDaysBefore,
            isActive: true
        ),
        isPresented: .constant(true)
    )
}
