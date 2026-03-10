import SwiftUI

struct RecurringExpenseEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var title: String
    @State private var description: String
    @State private var amount: String
    @State private var category: String
    @State private var selectedFrequency: RecurrenceFrequency
    @State private var startDate: Date
    @State private var endDate: Date?
    @State private var hasEndDate: Bool
    @State private var selectedReminder: ReminderOption
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    let expense: RecurringExpense
    var onClose: (() -> Void)? = nil

    private let frequencyOptions: [RecurrenceFrequency] = [
        .weekly, .biweekly, .monthly, .yearly
    ]

    init(expense: RecurringExpense, onClose: (() -> Void)? = nil) {
        self.expense = expense
        self.onClose = onClose

        _title = State(initialValue: expense.title)
        _description = State(initialValue: expense.description ?? "")
        _amount = State(initialValue: String(format: "%.2f", Double(truncating: expense.amount as NSDecimalNumber)))
        _category = State(initialValue: expense.category ?? "")
        _selectedFrequency = State(initialValue: expense.frequency)
        _startDate = State(initialValue: expense.startDate)
        _endDate = State(initialValue: expense.endDate)
        _hasEndDate = State(initialValue: expense.endDate != nil)
        _selectedReminder = State(initialValue: expense.reminderOption)
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(amount) != nil &&
        (Double(amount) ?? 0) > 0
    }

    private var pageBackground: Color {
        colorScheme == .dark ? Color.gmailDarkBackground : Color.white
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.09)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.62)
    }

    private var previewNextDate: Date {
        RecurringExpense.calculateNextOccurrence(from: startDate, frequency: selectedFrequency)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        headerCard
                        basicInfoSection
                        financialDetailsSection
                        scheduleSection
                        reminderSection

                        if showError {
                            errorSection
                        }
                    }
                    .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }

                actionButtonsSection
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Edit Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(selectedFrequency.displayName)
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    )

                Spacer()

                Text(expense.isActive ? "Active" : "Paused")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(expense.isActive ? .green : .orange)
            }

            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recurring Expense" : title)
                .font(FontManager.geist(size: 24, weight: .bold))
                .foregroundColor(primaryText)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("Next")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryText)

                Text(formattedDate(previewNextDate))
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)

                Text("•")
                    .foregroundColor(secondaryText.opacity(0.6))

                Text(CurrencyParser.formatAmount(Double(amount) ?? 0))
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(primaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private var basicInfoSection: some View {
        formSection(title: "Basic Info", subtitle: "Name and context") {
            labeledField("Title") {
                textInputField(placeholder: "e.g., Water heater maintenance", text: $title)
            }

            labeledField("Description") {
                TextField("Add details...", text: $description, axis: .vertical)
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(primaryText)
                    .lineLimit(3...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(fieldBackground)
                    )
            }
        }
    }

    private var financialDetailsSection: some View {
        formSection(title: "Details", subtitle: "Amount and category") {
            labeledField("Amount") {
                HStack(spacing: 8) {
                    Text("$")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(primaryText)

                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fieldBackground)
                )
            }

            labeledField("Category") {
                textInputField(placeholder: "e.g., Home, Utilities, Services", text: $category)
            }
        }
    }

    private var scheduleSection: some View {
        formSection(title: "Schedule", subtitle: "When it repeats") {
            labeledField("Start Date") {
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fieldBackground)
                )
            }

            labeledField("Recurrence Frequency") {
                HStack(spacing: 8) {
                    ForEach(frequencyOptions, id: \.self) { frequency in
                        frequencyChip(for: frequency)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $hasEndDate) {
                    Text("Set End Date")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(primaryText)
                }
                .toggleStyle(SwitchToggleStyle(tint: colorScheme == .dark ? .white : .black))

                if hasEndDate {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { endDate ?? startDate },
                            set: { endDate = $0 }
                        ),
                        in: startDate...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(fieldBackground)
                    )
                }
            }
            .padding(.top, 2)
        }
    }

    private var reminderSection: some View {
        formSection(title: "Reminder", subtitle: "Notify before due date") {
            Menu {
                ForEach(ReminderOption.allCases, id: \.self) { option in
                    Button(option.displayName) {
                        selectedReminder = option
                    }
                }
            } label: {
                HStack {
                    Text(selectedReminder.displayName)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(primaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fieldBackground)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var errorSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(.red)

            Text(errorMessage)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(primaryText)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.14))
        )
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                onClose?()
                dismiss()
            }) {
                Text("Cancel")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: saveChanges) {
                Text(isSaving ? "Saving..." : "Save Changes")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(isFormValid && !isSaving ? (colorScheme == .dark ? .black : .white) : .white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                isFormValid && !isSaving
                                ? (colorScheme == .dark ? Color.white : Color.black)
                                : Color.gray.opacity(0.35)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isFormValid || isSaving)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(pageBackground)
                .overlay(alignment: .top) {
                    Divider()
                        .overlay(borderColor.opacity(0.8))
                }
        )
    }

    @ViewBuilder
    private func formSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FontManager.geist(size: 17, weight: .semibold))
                    .foregroundColor(primaryText)

                Text(subtitle)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryText)
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(secondaryText)
            content()
        }
    }

    private func textInputField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(FontManager.geist(size: 15, weight: .regular))
            .foregroundColor(primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fieldBackground)
            )
    }

    private func frequencyChip(for frequency: RecurrenceFrequency) -> some View {
        let isSelected = selectedFrequency == frequency

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFrequency = frequency
            }
        }) {
            Text(frequency.displayName)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                            ? (colorScheme == .dark ? Color.white : Color.black)
                            : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
                var updatedExpense = expense
                updatedExpense.title = title.trimmingCharacters(in: .whitespaces)
                updatedExpense.description = description.isEmpty ? nil : description
                updatedExpense.amount = Decimal(amountDouble)
                updatedExpense.category = category.isEmpty ? nil : category
                updatedExpense.frequency = selectedFrequency
                updatedExpense.startDate = startDate
                updatedExpense.endDate = hasEndDate ? (endDate ?? startDate) : nil
                updatedExpense.reminderOption = selectedReminder
                updatedExpense.updatedAt = Date()
                updatedExpense.nextOccurrence = RecurringExpense.calculateNextOccurrence(
                    from: startDate,
                    frequency: selectedFrequency
                )

                _ = try await RecurringExpenseService.shared.updateRecurringExpense(updatedExpense)

                await MainActor.run {
                    isSaving = false
                    onClose?()
                    dismiss()
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
        )
    )
}
