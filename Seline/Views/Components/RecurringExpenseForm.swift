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

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Double(amount) ?? 0) > 0
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.gmailDarkBackground : Color.emailLightBackground
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.emailLightSectionCard
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }

    private var fieldFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.emailLightSurface
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color.emailLightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.emailLightTextSecondary
    }

    private var primaryButtonFill: Color {
        if isFormValid && !isSaving {
            return colorScheme == .dark ? Color.white : Color.black
        }
        return Color.gray.opacity(0.35)
    }

    private var primaryButtonText: Color {
        if isFormValid && !isSaving {
            return colorScheme == .dark ? .black : .white
        }
        return Color.white.opacity(0.9)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        introCard
                        basicInfoCard
                        detailsCard
                        scheduleCard
                        reminderCard

                        if showError {
                            errorCard
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)

                actionButtonsSection
            }
            .background(pageBackgroundColor.ignoresSafeArea())
            .navigationTitle("Recurring Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onChange(of: hasEndDate) { enabled in
                if enabled, endDate == nil {
                    endDate = startDate
                }
            }
            .onChange(of: startDate) { newDate in
                if let endDate, endDate < newDate {
                    self.endDate = newDate
                }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New recurring expense")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(primaryTextColor)

            Text("Track fixed costs with reminders and clean monthly projections.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private var basicInfoCard: some View {
        sectionCard(title: "Basic Info") {
            VStack(spacing: 12) {
                labeledInput(label: "Title", isRequired: true) {
                    TextField("Mortgage, internet, gym…", text: $title)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                }

                labeledInput(label: "Description", isRequired: false) {
                    TextField("Add details...", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
        }
    }

    private var detailsCard: some View {
        sectionCard(title: "Details") {
            VStack(spacing: 12) {
                labeledInput(label: "Amount", isRequired: true) {
                    HStack(spacing: 8) {
                        Text("$")
                            .font(FontManager.geist(size: 18, weight: .medium))
                            .foregroundColor(secondaryTextColor)

                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }

                labeledInput(label: "Category", isRequired: false) {
                    TextField("e.g., Utilities", text: $category)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                }
            }
        }
    }

    private var scheduleCard: some View {
        sectionCard(title: "Schedule") {
            VStack(spacing: 12) {
                dateRow(label: "Start Date", selection: $startDate, range: Date()...)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $hasEndDate) {
                        Text("Set End Date")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(primaryTextColor)
                    }
                    .tint(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black)

                    if hasEndDate {
                        dateRow(
                            label: "End Date",
                            selection: Binding(
                                get: { endDate ?? startDate },
                                set: { endDate = $0 }
                            ),
                            range: startDate...
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recurrence Frequency")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(secondaryTextColor)

                    Picker("Frequency", selection: $selectedFrequency) {
                        Text("Weekly").tag(RecurrenceFrequency.weekly)
                        Text("Bi-weekly").tag(RecurrenceFrequency.biweekly)
                        Text("Monthly").tag(RecurrenceFrequency.monthly)
                        Text("Yearly").tag(RecurrenceFrequency.yearly)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var reminderCard: some View {
        sectionCard(title: "Reminder") {
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
                        .foregroundColor(primaryTextColor)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldFillColor)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var errorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(errorMessage)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(primaryTextColor)
                .lineLimit(3)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(cardBorderColor)

            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(fieldFillColor)
                        )
                }

                Button(action: saveRecurringExpense) {
                    Text(isSaving ? "Creating..." : "Create")
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(primaryButtonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(primaryButtonFill)
                        )
                }
                .disabled(!isFormValid || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(pageBackgroundColor)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(primaryTextColor)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        )
    }

    private func labeledInput<Content: View>(
        label: String,
        isRequired: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                if isRequired {
                    Text("*")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
            }

            content()
                .font(FontManager.geist(size: 16, weight: .regular))
                .foregroundColor(primaryTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldFillColor)
                )
        }
    }

    private func dateRow(label: String, selection: Binding<Date>, range: PartialRangeFrom<Date>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(primaryTextColor)

            Spacer()

            DatePicker(
                "",
                selection: selection,
                in: range,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(primaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fieldFillColor)
        )
    }

    private func saveRecurringExpense() {
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

        showError = false
        isSaving = true

        Task {
            do {
                let nextOccurrence = RecurringExpense.calculateNextOccurrence(
                    from: startDate,
                    frequency: selectedFrequency
                )

                let recurringExpense = RecurringExpense(
                    userId: "",
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
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
                print("Error saving recurring expense: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    RecurringExpenseForm { expense in
        print("Saved expense: \(expense.title)")
    }
}
