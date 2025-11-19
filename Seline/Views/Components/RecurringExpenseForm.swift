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

    var body: some View {
        NavigationStack {
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
                            // Exclude daily frequency for recurring expenses
                            Text("Weekly").tag(RecurrenceFrequency.weekly)
                            Text("Bi-weekly").tag(RecurrenceFrequency.biweekly)
                            Text("Monthly").tag(RecurrenceFrequency.monthly)
                            Text("Yearly").tag(RecurrenceFrequency.yearly)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Start Date
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Start Date", systemImage: "calendar.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        DatePicker(
                            "Start Date",
                            selection: $startDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }

                    // End Date Toggle
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $hasEndDate) {
                            Label("Set End Date", systemImage: "calendar.badge.minus")
                                .font(.subheadline)
                                .fontWeight(.semibold)
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

                    // Save Button
                    Button(action: saveRecurringExpense) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isSaving ? "Creating..." : "Create Recurring Expense")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            (isFormValid && !isSaving)
                                ? Color.blue
                                : Color.gray.opacity(0.5)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!isFormValid || isSaving)
                }
                .padding(16)
            }
            .navigationTitle("New Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
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
