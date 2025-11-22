import SwiftUI

struct RecurringExpenseForm: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var amount: String = ""
    @State private var category: String = ""
    @State private var selectedFrequency: RecurrenceFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var endDate: Date?
    @State private var hasEndDate: Bool = false
    @State private var selectedReminder: ReminderOption = .none
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isSaving: Bool = false

    var onSave: (RecurringExpense) -> Void

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

            Button(action: saveRecurringExpense) {
                Text(isSaving ? "Creating..." : "Create Recurring Expense")
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
                    VStack(spacing: 24) {
                        // BASIC INFO Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Basic Info")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)

                            // Title
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Title")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                TextField("e.g., Netflix Subscription", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }

                            // Description
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description (Optional)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                TextField("Add notes...", text: $description)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        // DETAILS Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Details")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)

                            // Amount
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Amount")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
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
                                Text("Category (Optional)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                TextField("e.g., Entertainment", text: $category)
                                    .textFieldStyle(.roundedBorder)
                            }

                            // Start Date
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start Date")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                DatePicker(
                                    "Start Date",
                                    selection: $startDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                            }

                            // Frequency
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recurrence Frequency")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Picker("Frequency", selection: $selectedFrequency) {
                                    Text("Weekly").tag(RecurrenceFrequency.weekly)
                                    Text("Bi-weekly").tag(RecurrenceFrequency.biweekly)
                                    Text("Monthly").tag(RecurrenceFrequency.monthly)
                                    Text("Yearly").tag(RecurrenceFrequency.yearly)
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // ADVANCED Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Advanced")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)

                            // End Date Toggle
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $hasEndDate) {
                                    Text("Set End Date")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }

                                if hasEndDate {
                                    DatePicker(
                                        "End Date",
                                        selection: Binding(
                                            get: { endDate ?? Date() },
                                            set: { endDate = $0 }
                                        ),
                                        in: startDate...,
                                        displayedComponents: .date
                                    )
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                }
                            }

                            // Reminder Option
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Reminder")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Picker("Reminder", selection: $selectedReminder) {
                                    ForEach(ReminderOption.allCases, id: \.self) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

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
            .navigationTitle("New Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }

    private func saveRecurringExpense() {
        // Validate
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
                // Calculate next occurrence
                let nextOccurrence = RecurringExpense.calculateNextOccurrence(
                    from: startDate,
                    frequency: selectedFrequency
                )

                // Create recurring expense
                let recurringExpense = RecurringExpense(
                    userId: "", // Will be set by service
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description,
                    amount: Decimal(amountDouble),
                    category: category.isEmpty ? nil : category,
                    frequency: selectedFrequency,
                    startDate: startDate,
                    endDate: hasEndDate ? endDate : nil,
                    nextOccurrence: nextOccurrence,
                    reminderOption: selectedReminder,
                    isActive: true
                )

                // Save to database (includes auto-generating instances and scheduling reminders)
                let savedExpense = try await RecurringExpenseService.shared.createRecurringExpense(recurringExpense)

                await MainActor.run {
                    onSave(savedExpense)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
                print("❌ Error saving recurring expense: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    RecurringExpenseForm { expense in
        print("Saved expense: \(expense.title)")
    }
}
