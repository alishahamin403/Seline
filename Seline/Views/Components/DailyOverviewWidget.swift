import SwiftUI

struct DailyOverviewWidget: View {
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var quickNoteManager = QuickNoteManager.shared
    @Environment(\.colorScheme) var colorScheme

    @Binding var isExpanded: Bool
    @State private var expensesAndInstances: [(expense: RecurringExpense, instance: RecurringInstance)] = []
    @State private var showingAddQuickNote = false
    @State private var quickNoteText = ""
    @State private var editingQuickNote: QuickNote?
    @FocusState private var isQuickNoteFocused: Bool

    // Navigation callbacks
    var onNoteSelected: ((Note) -> Void)?
    var onEmailSelected: ((Email) -> Void)?
    var onTaskSelected: ((TaskItem) -> Void)?

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today)!
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: today)!
    }

    // MARK: - Data Filtering

    private var expensesDueToday: [(expense: RecurringExpense, instance: RecurringInstance)] {
        expensesAndInstances
            .filter { item in
                Calendar.current.isDate(item.instance.occurrenceDate, inSameDayAs: today) &&
                item.instance.status == .pending
            }
            .sorted { $0.expense.title < $1.expense.title }
    }

    private var expensesDueTomorrow: [(expense: RecurringExpense, instance: RecurringInstance)] {
        expensesAndInstances
            .filter { item in
                Calendar.current.isDate(item.instance.occurrenceDate, inSameDayAs: tomorrow) &&
                item.instance.status == .pending
            }
            .sorted { $0.expense.title < $1.expense.title }
    }

    private var upcomingExpenses: [(expense: RecurringExpense, instance: RecurringInstance)] {
        let calendar = Calendar.current
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!
        let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: today)!

        return expensesAndInstances
            .filter { item in
                let instanceDay = calendar.startOfDay(for: item.instance.occurrenceDate)
                return instanceDay >= dayAfterTomorrow &&
                       instanceDay < sevenDaysFromNow &&
                       item.instance.status == .pending
            }
            .sorted { $0.instance.occurrenceDate < $1.instance.occurrenceDate }
    }

    private var importantUnreadEmails: [Email] {
        emailService.inboxEmails
            .filter { $0.isImportant && !$0.isRead }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map { $0 }
    }

    private var birthdaysThisWeek: [TaskItem] {
        // OPTIMIZATION: Use CacheManager with 5-minute TTL
        return CacheManager.shared.getOrCompute(
            forKey: CacheManager.CacheKey.birthdaysThisWeek,
            ttl: CacheManager.TTL.medium
        ) {
            let birthdayTag = tagManager.tags.first { $0.name.lowercased() == "birthday" }

            return taskManager.getAllFlattenedTasks().filter { task in
                // Check if task has birthday tag or contains "birthday" in title
                let isBirthdayEvent = (birthdayTag != nil && task.tagId == birthdayTag?.id) ||
                                     task.title.lowercased().contains("birthday")

                guard isBirthdayEvent, let targetDate = task.targetDate else { return false }

                return targetDate >= today && targetDate < weekEnd
            }
            .sorted { ($0.targetDate ?? Date()) < ($1.targetDate ?? Date()) }
        }
    }

    private var todaysReceipts: [Note] {
        // OPTIMIZATION: Use CacheManager with 5-minute TTL to avoid repeated currency parsing
        return CacheManager.shared.getOrCompute(
            forKey: CacheManager.CacheKey.todaysReceipts,
            ttl: CacheManager.TTL.medium
        ) {
            let calendar = Calendar.current
            let receiptsFolder = notesManager.folders.first { $0.name == "Receipts" }

            return notesManager.notes.filter { note in
                // CRITICAL FIX: Only include notes that are in the Receipts folder hierarchy
                guard let folderId = note.folderId,
                      let receiptsFolderId = receiptsFolder?.id else {
                    return false
                }

                // Check if this note is in the Receipts folder or any of its subfolders
                var currentFolderId: UUID? = folderId
                var isInReceiptsFolder = false

                while let currentId = currentFolderId {
                    if currentId == receiptsFolderId {
                        isInReceiptsFolder = true
                        break
                    }
                    currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
                }

                guard isInReceiptsFolder else { return false }

                let content = note.content ?? ""
                let amount = CurrencyParser.extractAmount(from: content)
                guard amount > 0 else { return false }

                // CRITICAL: Only include notes with bullet point structure (receipt format)
                // Receipt notes must have bullet points (lines starting with "- ")
                guard content.contains("- ") else { return false }

                // FIXED: Always use dateCreated to determine if receipt was added today
                // The title may contain the receipt's original date (which could be old),
                // but we want to show receipts that were ADDED today, not DATED today
                let noteDay = calendar.startOfDay(for: note.dateCreated)
                return noteDay == today
            }.sorted { $0.dateCreated > $1.dateCreated }
        }
    }

    private var todaysTotalSpending: Double {
        // OPTIMIZATION: Use CacheManager with 5-minute TTL (same as receipts)
        return CacheManager.shared.getOrCompute(
            forKey: CacheManager.CacheKey.todaysSpending,
            ttl: CacheManager.TTL.medium
        ) {
            // Compute from cached receipts
            return todaysReceipts.compactMap { note in
                let amount = CurrencyParser.extractAmount(from: note.content ?? "")
                return amount > 0 ? amount : nil
            }.reduce(0.0, +)
        }
    }

    // MARK: - Computed Properties

    private var hasAnyContent: Bool {
        !expensesDueToday.isEmpty ||
        !expensesDueTomorrow.isEmpty ||
        !upcomingExpenses.isEmpty ||
        !importantUnreadEmails.isEmpty ||
        !birthdaysThisWeek.isEmpty ||
        !todaysReceipts.isEmpty ||
        !quickNoteManager.quickNotes.isEmpty ||
        true // Always show to allow adding quick notes
    }

    private var totalItemsCount: Int {
        expensesDueToday.count +
        expensesDueTomorrow.count +
        importantUnreadEmails.count +
        (birthdaysThisWeek.isEmpty ? 0 : 1) + // Count birthdays section as 1 if there are any
        (todaysReceipts.isEmpty ? 0 : 1) // Count today's spending as 1 if there are any
    }

    private var summaryText: String {
        var parts: [String] = []

        if !todaysReceipts.isEmpty {
            parts.append("\(CurrencyParser.formatAmount(todaysTotalSpending)) today")
        }
        if !expensesDueToday.isEmpty {
            parts.append("\(expensesDueToday.count) today")
        }
        if !expensesDueTomorrow.isEmpty {
            parts.append("\(expensesDueTomorrow.count) tom")
        }
        if !upcomingExpenses.isEmpty {
            parts.append("\(upcomingExpenses.count) upcoming")
        }
        if !importantUnreadEmails.isEmpty {
            parts.append("\(importantUnreadEmails.count) email\(importantUnreadEmails.count > 1 ? "s" : "")")
        }
        if !birthdaysThisWeek.isEmpty {
            parts.append("\(birthdaysThisWeek.count) birthday\(birthdaysThisWeek.count > 1 ? "s" : "")")
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Body

    var body: some View {
        if hasAnyContent {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                if isExpanded {
                    Divider()
                        .padding(.vertical, 12)
                        .opacity(0.3)

                    VStack(alignment: .leading, spacing: 16) {
                        if !todaysReceipts.isEmpty {
                            todaysSpendingSection
                        }

                        if !expensesDueToday.isEmpty {
                            expensesDueTodaySection
                        }

                        if !expensesDueTomorrow.isEmpty {
                            expensesDueTomorrowSection
                        }

                        if !upcomingExpenses.isEmpty {
                            upcomingExpensesSection
                        }

                        if !importantUnreadEmails.isEmpty {
                            importantEmailsSection
                        }

                        if !birthdaysThisWeek.isEmpty {
                            birthdaysSection
                        }

                        // Quick Notes section - always show at bottom
                        quickNotesSection
                    }
                }
            }
            .padding(16)
            .shadcnTileStyle(colorScheme: colorScheme)
            .onAppear {
                loadData()
                Task {
                    do {
                        try await quickNoteManager.fetchQuickNotes()
                    } catch {
                        print("Error loading quick notes: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
            HapticManager.shared.light()
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if !isExpanded {
                        Text(summaryText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    // MARK: - Section Views

    private var todaysSpendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total Spend Today: \(CurrencyParser.formatAmount(todaysTotalSpending))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(todaysReceipts.prefix(5), id: \.id) { note in
                receiptRow(note)
            }
        }
    }

    private var expensesDueTodaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Due Today")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(expensesDueToday.prefix(5), id: \.instance.id) { item in
                expenseRow(item.expense, instance: item.instance)
            }
        }
    }

    private var expensesDueTomorrowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Due Tomorrow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(expensesDueTomorrow.prefix(5), id: \.instance.id) { item in
                expenseRow(item.expense, instance: item.instance)
            }
        }
    }

    private var upcomingExpensesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming (Next 7 Days)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(upcomingExpenses.prefix(10), id: \.instance.id) { item in
                upcomingExpenseRow(item.expense, instance: item.instance)
            }
        }
    }

    private var importantEmailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Important Emails")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(importantUnreadEmails.prefix(3), id: \.id) { email in
                emailRow(email)
            }
        }
    }

    private var birthdaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Birthdays This Week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ForEach(birthdaysThisWeek.prefix(3), id: \.id) { birthday in
                birthdayRow(birthday)
            }
        }
    }

    private var quickNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with Quick Notes text and + button
            HStack(spacing: 12) {
                Text("Quick Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                if quickNoteManager.quickNotes.count < 4 {
                    Button(action: {
                        showingAddQuickNote = true
                        quickNoteText = ""
                        editingQuickNote = nil
                        isQuickNoteFocused = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
                }
            }

            if quickNoteManager.quickNotes.isEmpty && !showingAddQuickNote {
                Text("Tap + to add a quick note")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .italic()
            }

            if showingAddQuickNote || editingQuickNote != nil {
                quickNoteInput
            }

            ForEach(quickNoteManager.quickNotes.prefix(4), id: \.id) { note in
                quickNoteRow(note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.yellow.opacity(0.15) : Color.yellow.opacity(0.1))
        )
    }

    private var quickNoteInput: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Type your note...", text: $quickNoteText, axis: .vertical)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .focused($isQuickNoteFocused)
                .lineLimit(3...5)

            HStack(spacing: 8) {
                Button("Cancel") {
                    showingAddQuickNote = false
                    editingQuickNote = nil
                    quickNoteText = ""
                }
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()

                Button(editingQuickNote != nil ? "Update" : "Save") {
                    Task {
                        do {
                            if let editing = editingQuickNote {
                                try await quickNoteManager.updateQuickNote(editing, content: quickNoteText)
                            } else {
                                try await quickNoteManager.createQuickNote(content: quickNoteText)
                            }
                            showingAddQuickNote = false
                            editingQuickNote = nil
                            quickNoteText = ""
                        } catch {
                            print("Error saving quick note: \(error)")
                        }
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue)
                .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
                .disabled(quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func quickNoteRow(_ note: QuickNote) -> some View {
        HStack(spacing: 8) {
            Text(note.content)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                .lineLimit(2)

            Spacer()

            Menu {
                Button(action: {
                    editingQuickNote = note
                    quickNoteText = note.content
                    showingAddQuickNote = false
                    isQuickNoteFocused = true
                }) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive, action: {
                    Task {
                        do {
                            try await quickNoteManager.deleteQuickNote(note)
                        } catch {
                            print("Error deleting quick note: \(error)")
                        }
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Row Views

    private func expenseRow(_ expense: RecurringExpense, instance: RecurringInstance) -> some View {
        HStack(spacing: 8) {
            Text(expense.title)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))

            Spacer()

            Text(instance.formattedAmount)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    private func upcomingExpenseRow(_ expense: RecurringExpense, instance: RecurringInstance) -> some View {
        HStack(spacing: 8) {
            Text(expense.title)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))

            Spacer()

            Text(formatUpcomingDate(instance.occurrenceDate))
                .font(.system(size: 11))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))

            Text(instance.formattedAmount)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    private func emailRow(_ email: Email) -> some View {
        Button(action: {
            onEmailSelected?(email)
            HapticManager.shared.light()
        }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.subject)
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                        .lineLimit(1)

                    Text(email.sender.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private func birthdayRow(_ birthday: TaskItem) -> some View {
        Button(action: {
            onTaskSelected?(birthday)
            HapticManager.shared.light()
        }) {
            HStack(spacing: 8) {
                Text(birthday.title)
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                if let targetDate = birthday.targetDate {
                    Text(formatBirthdayDate(targetDate))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private func receiptRow(_ note: Note) -> some View {
        Button(action: {
            onNoteSelected?(note)
            HapticManager.shared.light()
        }) {
            HStack(spacing: 8) {
                Text(note.title)
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                let amount = CurrencyParser.extractAmount(from: note.content ?? "")
                if amount > 0 {
                    Text(CurrencyParser.formatAmount(amount))
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    // MARK: - Helper Methods

    private func loadData() {
        Task {
            do {
                let recurringExpenses = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
                let calendar = Calendar.current
                let now = Date()
                var items: [(expense: RecurringExpense, instance: RecurringInstance)] = []

                // Fetch instances within the next 7 days (to cover "tomorrow" and birthdays this week)
                let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now)!

                for expense in recurringExpenses {
                    let instances = try await RecurringExpenseService.shared.fetchInstances(for: expense.id)

                    for instance in instances {
                        let instanceDay = calendar.startOfDay(for: instance.occurrenceDate)

                        // Only include instances within the next 7 days
                        if instanceDay >= calendar.startOfDay(for: now) && instanceDay < sevenDaysFromNow {
                            items.append((expense: expense, instance: instance))
                        }
                    }
                }

                await MainActor.run {
                    expensesAndInstances = items
                }
            } catch {
                print("Error loading recurring expenses: \(error)")
            }
        }
    }

    private func formatBirthdayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatUpcomingDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

}

// MARK: - Preview

struct DailyOverviewWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            DailyOverviewWidget(isExpanded: .constant(false))
                .padding()
            Spacer()
        }
        .background(Color.gray.opacity(0.1))
    }
}
