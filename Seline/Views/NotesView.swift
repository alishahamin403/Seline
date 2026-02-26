import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers
import PDFKit

struct NotesView: View, Searchable {
    private enum HubPeriod: String, CaseIterable {
        case thisMonth = "This Month"
        case thisYear = "This Year"
    }

    private enum NotesMainPage: String, CaseIterable {
        case notes = "Notes"
        case receipts = "Receipts"
        case recurring = "Recurring"
    }

    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var showingNewNoteSheet = false
    @State private var selectedNote: Note? = nil
    @State private var navigationPath: [Note] = []
    @State private var isPinnedExpanded = true
    @State private var expandedSections: Set<String> = ["RECENT"]
    @State private var showingFolderSidebar = false
    @State private var selectedFolderId: UUID? = nil
    @State private var showUnfiledNotesOnly = false
    @State private var showReceiptStats = false
    @State private var selectedReceiptDrilldownMonth: Date? = nil
    @State private var showRecurringOverview = false
    @State private var showingRecurringExpenseForm = false
    @State private var showingReceiptAddOptions = false
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @StateObject private var openAIService = GeminiService.shared
    @Namespace private var tabAnimation
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var noteForReminder: Note? = nil
    @State private var recurringExpenses: [RecurringExpense] = []
    @State private var selectedMainPage: NotesMainPage = .notes
    @State private var hubPeriod: HubPeriod = .thisYear
    @State private var didLoadRecurringHubData = false
    // Cached filtered arrays to avoid recomputing on every body evaluation
    @State private var cachedFilteredPinned: [Note] = []
    @State private var cachedAllUnpinned: [Note] = []
    @State private var cachedRecentNotes: [Note] = []
    @State private var cachedNotesByMonth: [(month: String, notes: [Note])] = []

    var filteredPinnedNotes: [Note] {
        var notes: [Note]
        if searchText.isEmpty {
            notes = notesManager.pinnedNotes
        } else {
            notes = notesManager.searchNotes(query: searchText).filter { $0.isPinned }
        }

        // Filter by selected folder if one is selected
        if let folderId = selectedFolderId {
            notes = notes.filter { $0.folderId == folderId }
        }

        return notes
    }


    var allUnpinnedNotes: [Note] {
        var notes: [Note]
        if searchText.isEmpty {
            notes = notesManager.recentNotes
        } else {
            notes = notesManager.searchNotes(query: searchText).filter { !$0.isPinned }
        }

        // Filter by selected folder if one is selected
        if let folderId = selectedFolderId {
            notes = notes.filter { $0.folderId == folderId }
        }

        return notes
    }

    // Notes updated in the last 7 days (excluding receipts)
    var recentNotes: [Note] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })

        return allUnpinnedNotes.filter { note in
            // Include if updated in last 7 days AND not in Receipts folder
            guard note.dateModified >= oneWeekAgo else { return false }

            // Check if note is in Receipts folder (or a subfolder of Receipts)
            if let folderId = note.folderId, let receiptsFolderId = receiptsFolder?.id {
                var currentFolderId: UUID? = folderId
                while let currentId = currentFolderId {
                    if currentId == receiptsFolderId {
                        return false // This is a receipt, exclude it
                    }
                    currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
                }
            }

            return true
        }
    }

    // Group older notes by month (excluding receipts)
    var notesByMonth: [(month: String, notes: [Note])] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })

        let olderNotes = allUnpinnedNotes.filter { note in
            // Include if older than 7 days AND not in Receipts folder
            guard note.dateModified < oneWeekAgo else { return false }

            // Check if note is in Receipts folder (or a subfolder of Receipts)
            if let folderId = note.folderId, let receiptsFolderId = receiptsFolder?.id {
                var currentFolderId: UUID? = folderId
                while let currentId = currentFolderId {
                    if currentId == receiptsFolderId {
                        return false // This is a receipt, exclude it
                    }
                    currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
                }
            }

            return true
        }

        // Group by month and year
        let grouped = Dictionary(grouping: olderNotes) { note -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: note.dateModified)
        }

        // Sort by date (most recent first)
        return grouped.map { (month: $0.key, notes: $0.value) }
            .sorted { first, second in
                guard let firstDate = first.notes.first?.dateModified,
                      let secondDate = second.notes.first?.dateModified else {
                    return false
                }
                return firstDate > secondDate
            }
    }

    private func refreshNoteCaches() {
        cachedFilteredPinned = filteredPinnedNotes
        cachedAllUnpinned = allUnpinnedNotes
        cachedRecentNotes = recentNotes
        cachedNotesByMonth = notesByMonth
    }

    var hasReceipts: Bool {
        let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })
        guard let receiptsFolderId = receiptsFolder?.id else { return false }
        return notesManager.notes.contains { note in
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
    }

    private var hubReceiptYear: Int {
        let calendar = Calendar.current
        switch hubPeriod {
        case .thisMonth, .thisYear:
            return calendar.component(.year, from: Date())
        }
    }

    private var hubReceiptSummary: YearlyReceiptSummary? {
        notesManager.getReceiptStatistics(year: hubReceiptYear).first
            ?? notesManager.getReceiptStatistics().first
    }

    private var hubReceiptMonthlySummaries: [MonthlyReceiptSummary] {
        guard let hubReceiptSummary else { return [] }
        switch hubPeriod {
        case .thisMonth:
            return Array(hubReceiptSummary.monthlySummaries.prefix(1))
        case .thisYear:
            return hubReceiptSummary.monthlySummaries
        }
    }

    private var hubReceiptTotal: Double {
        hubReceiptMonthlySummaries.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var hubReceiptCount: Int {
        hubReceiptMonthlySummaries.reduce(0) { $0 + $1.receipts.count }
    }

    private var hubTopReceiptCategories: [(category: String, total: Double)] {
        let receipts = hubReceiptMonthlySummaries.flatMap { $0.receipts }
        guard !receipts.isEmpty else { return [] }

        var totals: [String: Double] = [:]
        for receipt in receipts {
            let inferredCategory = ReceiptCategorizationService.shared.quickCategorizeReceipt(
                title: receipt.title,
                content: nil
            ) ?? "Other"
            totals[inferredCategory, default: 0] += receipt.amount
        }

        return totals
            .map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var activeRecurringExpenses: [RecurringExpense] {
        recurringExpenses
            .filter { $0.isActive }
            .sorted { $0.nextOccurrence < $1.nextOccurrence }
    }

    private var hubRecurringExpenses: [RecurringExpense] {
        let calendar = Calendar.current
        let now = Date()

        switch hubPeriod {
        case .thisMonth:
            return activeRecurringExpenses.filter {
                calendar.isDate($0.nextOccurrence, equalTo: now, toGranularity: .month)
            }
        case .thisYear:
            return activeRecurringExpenses
        }
    }

    private var recurringHubTotal: Double {
        switch hubPeriod {
        case .thisMonth:
            return hubRecurringExpenses.reduce(0) { total, expense in
                total + Double(truncating: expense.amount as NSDecimalNumber)
            }
        case .thisYear:
            return hubRecurringExpenses.reduce(0) { total, expense in
                total + Double(truncating: expense.yearlyAmount as NSDecimalNumber)
            }
        }
    }

    private var upcomingRecurringCount: Int {
        let calendar = Calendar.current
        let now = Date()
        switch hubPeriod {
        case .thisMonth:
            return hubRecurringExpenses.filter {
                calendar.isDate($0.nextOccurrence, equalTo: now, toGranularity: .month)
            }.count
        case .thisYear:
            return hubRecurringExpenses.count
        }
    }

    private var hubPinnedNotes: [Note] {
        notesManager.pinnedNotes
            .filter { !isReceiptNote($0) }
            .sorted { $0.dateModified > $1.dateModified }
    }

    private var hubUnfiledNotes: [Note] {
        notesManager.notes
            .filter { !$0.isPinned && $0.folderId == nil && !isReceiptNote($0) }
            .sorted { $0.dateModified > $1.dateModified }
    }

    private var hubFolderNotes: [Note] {
        guard let selectedFolderId else { return [] }
        return notesManager.notes
            .filter { $0.folderId == selectedFolderId && !isReceiptNote($0) }
            .sorted { $0.dateModified > $1.dateModified }
    }

    private var hubDisplayedNotes: [Note] {
        if showUnfiledNotesOnly {
            return hubUnfiledNotes
        }

        if selectedFolderId != nil {
            return hubFolderNotes
        }

        return hubPinnedNotes
    }

    private var notesSectionTitle: String {
        if showUnfiledNotesOnly {
            return "UNFILED NOTES"
        }

        if let selectedFolderId,
           let folderName = notesManager.folders.first(where: { $0.id == selectedFolderId })?.name {
            return folderName.uppercased()
        }

        return "PINNED NOTES"
    }

    private func isReceiptNote(_ note: Note) -> Bool {
        guard let receiptsFolderId = notesManager.folders.first(where: { $0.name == "Receipts" })?.id,
              let folderId = note.folderId else { return false }

        var currentFolderId: UUID? = folderId
        while let currentId = currentFolderId {
            if currentId == receiptsFolderId { return true }
            currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header section with search
                    VStack(spacing: 0) {
                        if !isSearchActive {
                            HStack(spacing: 10) {
                                Button(action: {
                                    HapticManager.shared.buttonTap()
                                    showingFolderSidebar = true
                                }) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .frame(width: 40, height: 36)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.appChip(colorScheme))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())

                                notesPageTabSelector
                                    .frame(maxWidth: .infinity)

                                Color.clear
                                .frame(width: 40, height: 36)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.appSurface(colorScheme))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                            .padding(.top, -4)
                            .padding(.bottom, 10)
                        }

                        if isSearchActive {
                            VStack(spacing: 0) {
                                UnifiedSearchBar(
                                    searchText: $searchText,
                                    isFocused: $isSearchFocused,
                                    placeholder: selectedMainPage == .notes
                                        ? "Search notes"
                                        : (selectedMainPage == .receipts ? "Search receipts" : "Search recurring expenses"),
                                    onCancel: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isSearchActive = false
                                            isSearchFocused = false
                                            searchText = ""
                                        }
                                    },
                                    colorScheme: colorScheme
                                )
                                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                                .padding(.top, 8)
                            }
                            .padding(.bottom, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .background(
                        Color.appBackground(colorScheme)
                    )

                    mainTabContent
                        .blur(radius: isSearchActive && !searchText.isEmpty ? 8 : 0)
                        .allowsHitTesting(!(isSearchActive && !searchText.isEmpty))

                Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 0)
                .background(
                    Color.appBackground(colorScheme)
                        .ignoresSafeArea()
                )
                .overlay(alignment: .top) {
                    if isSearchActive && !searchText.isEmpty {
                        searchResultsOverlay
                    }
                }
                .overlay(alignment: .leading) {
                    interactiveFolderSidebarOverlay(geometry: geometry)
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteEditView(note: note, isPresented: .constant(true))
            }
            .navigationDestination(isPresented: $showReceiptStats) {
                ReceiptStatsView(
                    searchText: nil,
                    initialMonthDate: selectedReceiptDrilldownMonth,
                    onAddReceipt: {
                        HapticManager.shared.buttonTap()
                        showingReceiptAddOptions = true
                    }
                )
                    .navigationTitle("Receipts")
                    .navigationBarTitleDisplayMode(.inline)
                    .onDisappear {
                        selectedReceiptDrilldownMonth = nil
                    }
            }
            .navigationDestination(isPresented: $showRecurringOverview) {
                RecurringExpenseStatsContent(searchText: nil)
                    .navigationTitle("Recurring")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .animation(nil, value: navigationPath.count)
            .overlay(alignment: .top) {
                if receiptProcessingState != .idle {
                    VStack {
                        ReceiptProcessingToast(state: receiptProcessingState)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(1000)
                }
            }
        }
        .onAppear {
            refreshNoteCaches()
            loadRecurringHubDataIfNeeded()
        }
        .onChange(of: searchText) { _ in refreshNoteCaches() }
        .onChange(of: selectedFolderId) { _ in refreshNoteCaches() }
        .onChange(of: showUnfiledNotesOnly) { _ in refreshNoteCaches() }
        .onReceive(notesManager.objectWillChange) { _ in refreshNoteCaches() }
        .swipeDownToRevealSearch(
            enabled: !isSearchActive,
            topRegion: UIScreen.main.bounds.height * 0.22,
            minimumDistance: 70
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = true
                isSearchFocused = true
            }
        }
        .swipeUpToDismissSearch(
            enabled: isSearchActive && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            topRegion: UIScreen.main.bounds.height * 0.28,
            minimumDistance: 54
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = false
                isSearchFocused = false
                searchText = ""
            }
        }
        .fullScreenCover(isPresented: $showingNewNoteSheet, onDismiss: {
            notesManager.isViewingNoteInNavigation = false
        }) {
            NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
        }
        .sheet(isPresented: $showingRecurringExpenseForm) {
            RecurringExpenseForm { expense in
                HapticManager.shared.buttonTap()
                print("Created recurring expense: \(expense.title)")
            }
            .presentationBg()
        }

        .sheet(item: $noteForReminder) { note in
            NoteReminderSheet(
                note: note,
                onSave: { date, message in
                    var updatedNote = note
                    updatedNote.reminderDate = date
                    updatedNote.reminderNote = message.isEmpty ? nil : message
                    notesManager.updateNote(updatedNote)
                    
                    // Invalidate widget cache
                    CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.upcomingNoteReminders)
                    
                    // Haptic feedback
                    HapticManager.shared.success()
                    
                    // TODO: Schedule local notification if needed
                },
                onRemove: {
                    var updatedNote = note
                    updatedNote.reminderDate = nil
                    updatedNote.reminderNote = nil
                    notesManager.updateNote(updatedNote)
                    
                    // Invalidate widget cache
                    CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.upcomingNoteReminders)
                    
                    HapticManager.shared.success()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReceiptImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        processReceiptImageDirectly(image)
                    }
                }
            ))
        }
        .sheet(isPresented: $showingReceiptCameraPicker) {
            CameraPicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        processReceiptImageDirectly(image)
                    }
                }
            ))
        }
        .confirmationDialog("Add Receipt", isPresented: $showingReceiptAddOptions, titleVisibility: .visible) {
            Button("Scan Receipt (Camera)") {
                HapticManager.shared.buttonTap()
                showingReceiptCameraPicker = true
            }
            Button("Import Receipt (Gallery)") {
                HapticManager.shared.buttonTap()
                showingReceiptImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Receipt Processing Helper
    
    private func processReceiptImageDirectly(_ image: UIImage) {
        Task {
            // Show processing indicator
            await MainActor.run {
                receiptProcessingState = .processing
            }
            
            do {
                let (receiptTitle, receiptContent) = try await openAIService.analyzeReceiptImage(image)
                
                // Clean up the extracted content
                let cleanedContent = receiptContent
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                
                // Extract month and year from receipt title for automatic folder organization
                var folderIdForReceipt: UUID?
                if let (month, year) = notesManager.extractMonthYearFromTitle(receiptTitle) {
                    folderIdForReceipt = await notesManager.getOrCreateReceiptMonthFolderAsync(month: month, year: year)
                } else {
                    let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
                    folderIdForReceipt = receiptsFolderId
                }
                
                await MainActor.run {
                    // Create note with receipt content
                    var newNote = Note(title: receiptTitle, content: cleanedContent, folderId: folderIdForReceipt)
                    
                    // Save note first, then upload image
                    Task {
                        let syncSuccess = await notesManager.addNoteAndWaitForSync(newNote)
                        
                        if syncSuccess {
                            // Upload image
                            let imageUrls = await notesManager.uploadNoteImages([image], noteId: newNote.id)
                            
                            // Update note with image URL
                            var updatedNote = newNote
                            updatedNote.imageUrls = imageUrls
                            updatedNote.dateModified = Date()
                            let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
                            
                            await MainActor.run {
                                HapticManager.shared.success()
                                receiptProcessingState = .success
                                print("✅ Receipt processed and saved directly")
                                
                                // Hide success message after 2 seconds
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    await MainActor.run {
                                        receiptProcessingState = .idle
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                receiptProcessingState = .error("Failed to save receipt")
                                HapticManager.shared.error()
                                
                                // Hide error message after 3 seconds
                                Task {
                                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                                    await MainActor.run {
                                        receiptProcessingState = .idle
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    receiptProcessingState = .error(error.localizedDescription)
                    HapticManager.shared.error()
                    print("❌ Error processing receipt: \(error.localizedDescription)")
                    
                    // Hide error message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            receiptProcessingState = .idle
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mainTabContent: some View {
        switch selectedMainPage {
        case .notes:
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    notesTabContent

                    Spacer()
                        .frame(height: 80)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
        case .receipts:
            receiptsTabContent
        case .recurring:
            recurringTabContent
        }
    }

    private var notesPageTabSelector: some View {
        HStack(spacing: 6) {
            ForEach(NotesMainPage.allCases, id: \.self) { page in
                let isSelected = selectedMainPage == page

                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedMainPage = page
                    }
                }) {
                    Text(page.rawValue)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(tabForegroundColor(isSelected: isSelected))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(tabBackgroundColor())
                                    .matchedGeometryEffect(id: "notesMainTab", in: tabAnimation)
                            }
                        }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(tabContainerColor())
                .overlay(
                    Capsule()
                        .stroke(tabContainerStrokeColor(), lineWidth: 1)
                )
        )
    }

    // MARK: - Unified Hub

    private var unifiedHubContent: some View {
        Group {
            hubNotesSection
            hubReceiptsSection
            hubRecurringSection
        }
    }

    private var hubNotesSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(
                title: notesSectionTitle,
                count: hubDisplayedNotes.count,
                addAction: {
                    HapticManager.shared.buttonTap()
                    openNewNoteEditor()
                }
            )

            if hubDisplayedNotes.isEmpty {
                hubEmptyState(
                    icon: "note.text",
                    title: showUnfiledNotesOnly ? "No unfiled notes" : "No pinned notes",
                    subtitle: showUnfiledNotesOnly ? "All loose notes are cleared" : "Pin notes to keep them here"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(hubDisplayedNotes.prefix(6)), id: \.id) { note in
                    NoteRow(
                        note: note,
                        onPinToggle: { note in
                            notesManager.togglePinStatus(note)
                        },
                        onTap: { note in
                            navigationPath.append(note)
                        },
                        onDelete: { note in
                            notesManager.deleteNote(note)
                        },
                        onSetReminder: { note in
                            noteForReminder = note
                        }
                    )
                }
            }
        }
        .background(notesSectionCardBackground)
    }

    private var hubReceiptsSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(
                title: hubPeriod == .thisMonth ? "RECEIPTS · THIS MONTH" : "RECEIPTS · THIS YEAR",
                count: hubReceiptCount,
                addAction: {
                    HapticManager.shared.buttonTap()
                    showingReceiptAddOptions = true
                }
            )

            if hubReceiptCount == 0 {
                hubEmptyState(
                    icon: "receipt",
                    title: "No receipts yet",
                    subtitle: "Scan or import a receipt to get started"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(
                        label: "Total",
                        value: CurrencyParser.formatAmountNoDecimals(hubReceiptTotal)
                    )
                    hubStatPill(
                        label: "Receipts",
                        value: "\(hubReceiptCount)"
                    )
                    hubStatPill(
                        label: "Top",
                        value: hubTopReceiptCategories.first?.category ?? "-"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                if !hubTopReceiptCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top categories")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(hubSecondaryTextColor)

                        ForEach(Array(hubTopReceiptCategories.prefix(3)), id: \.category) { item in
                            hubCategoryRow(category: item.category, total: item.total)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                if !hubReceiptMonthlySummaries.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(hubReceiptMonthlySummaries.prefix(hubPeriod == .thisMonth ? 1 : 3)), id: \.monthDate) { month in
                            hubMonthSnapshotRow(month)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }

            Button(action: {
                HapticManager.shared.buttonTap()
                selectedReceiptDrilldownMonth = nil
                showReceiptStats = true
            }) {
                Text("Open detailed receipts")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubAccentButtonTextColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(hubAccentColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
        }
        .background(notesSectionCardBackground)
    }

    private var hubRecurringSection: some View {
        VStack(spacing: 0) {
            hubCardHeader(
                title: hubPeriod == .thisMonth ? "RECURRING · THIS MONTH" : "RECURRING · THIS YEAR",
                count: hubRecurringExpenses.count,
                addAction: {
                    HapticManager.shared.buttonTap()
                    showingRecurringExpenseForm = true
                }
            )

            if hubRecurringExpenses.isEmpty {
                hubEmptyState(
                    icon: "repeat.circle",
                    title: "No recurring expenses",
                    subtitle: "Add one to track monthly fixed costs"
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else {
                HStack(spacing: 8) {
                    hubStatPill(
                        label: hubPeriod == .thisMonth ? "Monthly" : "Yearly",
                        value: CurrencyParser.formatAmountNoDecimals(recurringHubTotal)
                    )
                    hubStatPill(
                        label: "Active",
                        value: "\(hubRecurringExpenses.count)"
                    )
                    hubStatPill(
                        label: "In Period",
                        value: "\(upcomingRecurringCount)"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                VStack(spacing: 8) {
                    ForEach(Array(hubRecurringExpenses.prefix(4)), id: \.id) { expense in
                        hubRecurringRow(expense)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Button(action: {
                HapticManager.shared.buttonTap()
                showRecurringOverview = true
            }) {
                Text("Open recurring details")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubAccentButtonTextColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(hubAccentColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
        }
        .background(notesSectionCardBackground)
        .onAppear {
            loadRecurringHubDataIfNeeded()
        }
    }

    private func hubCardHeader(title: String, count: Int, addAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(hubSecondaryTextColor)
                .textCase(.uppercase)
                .tracking(0.6)

            if count > 0 {
                Text("· \(count)")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(hubSecondaryTextColor)
            }

            Spacer()

            if let addAction {
                Button(action: addAction) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.appChip(colorScheme))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func hubStatPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(hubSecondaryTextColor)

            Text(value)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appInnerSurface(colorScheme))
        )
    }

    private func hubCategoryRow(category: String, total: Double) -> some View {
        let ratio = hubReceiptTotal > 0 ? min(max(total / hubReceiptTotal, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(category)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)
                Spacer()
                Text(CurrencyParser.formatAmountNoDecimals(total))
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appBorder(colorScheme).opacity(0.75))

                    Capsule()
                        .fill(hubAccentColor)
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
    }

    private func hubMonthSnapshotRow(_ monthlySummary: MonthlyReceiptSummary) -> some View {
        Button(action: {
            HapticManager.shared.buttonTap()
            selectedReceiptDrilldownMonth = monthlySummary.monthDate
            showReceiptStats = true
        }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthlySummary.month)
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(hubPrimaryTextColor)
                        .lineLimit(1)
                    Text("\(monthlySummary.receipts.count) receipts")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(hubSecondaryTextColor)
                }

                Spacer()

                Text(CurrencyParser.formatAmountNoDecimals(monthlySummary.monthlyTotal))
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appInnerSurface(colorScheme))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func hubRecurringRow(_ expense: RecurringExpense) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(hubPrimaryTextColor)
                    .lineLimit(1)

                Text("\(recurringDueText(for: expense.nextOccurrence)) · \(expense.frequency.displayName)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(hubSecondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            Text(expense.formattedAmount)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appInnerSurface(colorScheme))
        )
    }

    private func hubEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(hubSecondaryTextColor)
            Text(title)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(hubPrimaryTextColor)
            Text(subtitle)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(hubSecondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var hubPrimaryTextColor: Color {
        Color.appTextPrimary(colorScheme)
    }

    private var hubSecondaryTextColor: Color {
        Color.appTextSecondary(colorScheme)
    }

    private var hubAccentColor: Color {
        colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent
    }

    private var hubAccentButtonTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func recurringDueText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func loadRecurringHubDataIfNeeded() {
        guard !didLoadRecurringHubData else { return }
        Task {
            await refreshRecurringHubData()
        }
    }

    @MainActor
    private func refreshRecurringHubData() async {
        do {
            recurringExpenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
            didLoadRecurringHubData = true
        } catch {
            didLoadRecurringHubData = false
            print("Failed to load recurring expenses: \(error)")
        }
    }

    // MARK: - Legacy Tab Content Views

    private var notesTabContent: some View {
        Group {
                        // Pinned section card
                        VStack(spacing: 0) {
                            ZStack(alignment: .trailing) {
                                NoteSectionHeader(
                                    title: "PINNED",
                                    count: cachedFilteredPinned.count,
                                    isExpanded: $isPinnedExpanded
                                )

                                Button(action: {
                                    HapticManager.shared.buttonTap()
                                    openNewNoteEditor()
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            Circle()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("New note")
                                .padding(.trailing, 14)
                            }

                            if isPinnedExpanded {
                                ForEach(cachedFilteredPinned) { note in
                                    NoteRow(
                                        note: note,
                                        onPinToggle: { note in
                                            notesManager.togglePinStatus(note)
                                        },
                                        onTap: { note in
                                            navigationPath.append(note)
                                        },
                                        onDelete: { note in
                                            notesManager.deleteNote(note)
                                        },
                                        onSetReminder: { note in
                                            noteForReminder = note
                                        }
                                    )
                                }
                            }
                        }
                        .background(
                            notesSectionCardBackground
                        )

                        // Recent section card (last 7 days)
                        if !cachedRecentNotes.isEmpty {
                            VStack(spacing: 0) {
                                NoteSectionHeader(
                                    title: "RECENT",
                                    count: cachedRecentNotes.count,
                                    isExpanded: Binding(
                                        get: { expandedSections.contains("RECENT") },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedSections.insert("RECENT")
                                            } else {
                                                expandedSections.remove("RECENT")
                                            }
                                        }
                                    )
                                )

                                if expandedSections.contains("RECENT") {
                                    ForEach(cachedRecentNotes) { note in
                                        NoteRow(
                                            note: note,
                                            onPinToggle: { note in
                                                notesManager.togglePinStatus(note)
                                            },
                                            onTap: { note in
                                                navigationPath.append(note)
                                            },
                                            onDelete: { note in
                                                notesManager.deleteNote(note)
                                            },
                                            onSetReminder: { note in
                                                noteForReminder = note
                                            }
                                        )
                                    }
                                }
                            }
                            .background(
                                notesSectionCardBackground
                            )
                        }

                        // Monthly sections for older notes
                        ForEach(cachedNotesByMonth.indices, id: \.self) { index in
                            let monthGroup = cachedNotesByMonth[index]

                            VStack(spacing: 0) {
                                NoteSectionHeader(
                                    title: monthGroup.month.uppercased(),
                                    count: monthGroup.notes.count,
                                    isExpanded: Binding(
                                        get: { expandedSections.contains(monthGroup.month) },
                                        set: { isExpanded in
                                            if isExpanded {
                                                expandedSections.insert(monthGroup.month)
                                            } else {
                                                expandedSections.remove(monthGroup.month)
                                            }
                                        }
                                    )
                                )

                                if expandedSections.contains(monthGroup.month) {
                                    ForEach(monthGroup.notes) { note in
                                        NoteRow(
                                            note: note,
                                            onPinToggle: { note in
                                                notesManager.togglePinStatus(note)
                                            },
                                            onTap: { note in
                                                navigationPath.append(note)
                                            },
                                            onDelete: { note in
                                                notesManager.deleteNote(note)
                                            },
                                            onSetReminder: { note in
                                                noteForReminder = note
                                            }
                                        )
                                    }
                                }
                            }
                            .background(
                                notesSectionCardBackground
                            )
                        }

            // Empty state for notes tab
            if cachedFilteredPinned.isEmpty && cachedRecentNotes.isEmpty && cachedNotesByMonth.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(FontManager.geist(size: 48, weight: .light))
                        .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.6))

                    Text(searchText.isEmpty ? "No notes yet" : "No notes found")
                        .font(FontManager.geist(size: 18, weight: .medium))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    if searchText.isEmpty {
                        Text("Tap the + button to create your first note")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 60)
            }
        }
    }
    
    // MARK: - Search Results Dropdown
    private var searchResultsOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14)
                .onTapGesture {
                    isSearchFocused = false
                }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if selectedMainPage == .notes {
                        searchResultsDropdown
                    } else if selectedMainPage == .receipts {
                        receiptSearchResults
                    } else {
                        recurringExpenseSearchResults
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .padding(.top, 64)
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity)
        .zIndex(200)
    }

    private var searchResultsDropdown: some View {
        let searchResults = notesManager.searchNotes(query: searchText).prefix(10)
        
        return VStack(spacing: 0) {
            if searchResults.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                    Text("No results for \"\(searchText)\"")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(searchResults), id: \.id) { note in
                    Button(action: {
                        HapticManager.shared.buttonTap()
                        searchText = ""
                        isSearchActive = false
                        navigationPath.append(note)
                    }) {
                        HStack(spacing: 12) {
                            // Icon
                            Image(systemName: note.isPinned ? "pin.fill" : "doc.text")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(note.isPinned ? .primary : .secondary)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(FontManager.geist(size: 15, weight: .medium))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                    .lineLimit(1)
                                
                                Text(note.content.prefix(50).replacingOccurrences(of: "\n", with: " "))
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Date
                            Text(note.dateModified.formatted(.relative(presentation: .named)))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if searchResults.last?.id != note.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 8)
    }

    private var receiptSearchResults: some View {
        let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })
        let receiptsFolderId = receiptsFolder?.id

        let filteredReceipts = notesManager.searchNotes(query: searchText)
            .filter { note in
                guard let folderId = note.folderId, let receiptsFolderId = receiptsFolderId else { return false }
                var currentFolderId: UUID? = folderId
                while let currentId = currentFolderId {
                    if currentId == receiptsFolderId {
                        return true
                    }
                    currentFolderId = notesManager.folders.first(where: { $0.id == currentId })?.parentFolderId
                }
                return false
            }
            .prefix(10)

        return receiptSearchResultsContent(filteredReceipts: Array(filteredReceipts))
    }

    @ViewBuilder
    private func receiptSearchResultsContent(filteredReceipts: [Note]) -> some View {
        VStack(spacing: 0) {
            if filteredReceipts.isEmpty {
                emptyReceiptState
            } else {
                receiptResultsList(filteredReceipts: filteredReceipts)
            }
        }
        .background(searchResultsBackground)
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 8)
    }

    private var emptyReceiptState: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
            Text("No receipts match your search")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func receiptResultsList(filteredReceipts: [Note]) -> some View {
        ForEach(filteredReceipts, id: \.id) { note in
            Button(action: {
                HapticManager.shared.buttonTap()
                searchText = ""
                isSearchActive = false
                navigationPath.append(note)
            }) {
                receiptRow(note: note)
            }
            .buttonStyle(PlainButtonStyle())

            if filteredReceipts.last?.id != note.id {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    private func receiptRow(note: Note) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "receipt")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled Receipt" : note.title)
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)

                Text(note.content.prefix(50).replacingOccurrences(of: "\n", with: " "))
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            Text(note.dateModified.formatted(.relative(presentation: .named)))
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchResultsBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.appSurface(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 8, x: 0, y: 4)
    }

    private var recurringExpenseSearchResults: some View {
        let filtered = recurringExpenses.filter { expense in
            let lowercased = searchText.lowercased()
            return expense.title.lowercased().contains(lowercased) ||
                   expense.category?.lowercased().contains(lowercased) ?? false ||
                   expense.description?.lowercased().contains(lowercased) ?? false
        }.prefix(10)

        return recurringExpenseSearchResultsContent(filtered: Array(filtered))
    }

    @ViewBuilder
    private func recurringExpenseSearchResultsContent(filtered: [RecurringExpense]) -> some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                emptyRecurringExpenseState
            } else {
                recurringExpenseResultsList(filtered: filtered)
            }
        }
        .background(searchResultsBackground)
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 8)
        .onAppear {
            Task {
                do {
                    recurringExpenses = try await RecurringExpenseService.shared.fetchAllRecurringExpenses()
                } catch {
                    print("Failed to load recurring expenses: \(error)")
                }
            }
        }
    }

    private var emptyRecurringExpenseState: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
            Text("No recurring expenses match your search")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func recurringExpenseResultsList(filtered: [RecurringExpense]) -> some View {
        ForEach(filtered, id: \.id) { expense in
            Button(action: {
                HapticManager.shared.buttonTap()
                searchText = ""
                isSearchActive = false
            }) {
                recurringExpenseRow(expense: expense)
            }
            .buttonStyle(PlainButtonStyle())

            if filtered.last?.id != expense.id {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    private func recurringExpenseRow(expense: RecurringExpense) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let category = expense.category {
                        Text(category)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                    Text("$\(String(format: "%.2f", Double(truncating: expense.amount as NSDecimalNumber)))")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
            }

            Spacer()

            Text(expense.frequency.displayName)
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var receiptsTabContent: some View {
        ReceiptStatsView(
            searchText: searchText.isEmpty ? nil : searchText,
            onAddReceipt: {
                HapticManager.shared.buttonTap()
                showingReceiptAddOptions = true
            }
        )
            .padding(.horizontal, -8) // Remove padding since content has its own
    }

    private var recurringTabContent: some View {
        RecurringExpenseStatsContent(
            searchText: searchText.isEmpty ? nil : searchText,
            onAddRecurring: {
                HapticManager.shared.buttonTap()
                showingRecurringExpenseForm = true
            }
        )
            .padding(.horizontal, -8) // Remove padding since content has its own
    }

    // MARK: - Helper Views

    private var notesSectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.appSectionCard(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 2
            )
    }

    private func openNewNoteEditor() {
        // Set this before presentation to prevent bottom-tab overlap during the transition.
        notesManager.isViewingNoteInNavigation = true
        showingNewNoteSheet = true
    }

    private func performMainPageAddAction() {
        HapticManager.shared.buttonTap()
        switch selectedMainPage {
        case .notes:
            openNewNoteEditor()
        case .receipts:
            showingReceiptAddOptions = true
        case .recurring:
            showingRecurringExpenseForm = true
        }
    }

    private var mainPageAddButtonAccessibilityLabel: String {
        switch selectedMainPage {
        case .notes:
            return "New note"
        case .receipts:
            return "Add receipt"
        case .recurring:
            return "Add recurring expense"
        }
    }

    private var mainPageAddButtonTitle: String {
        switch selectedMainPage {
        case .notes:
            return "New note"
        case .receipts:
            return "Add receipt"
        case .recurring:
            return "Add recurring"
        }
    }

    private var mainPageBodyAddActionRow: some View {
        HStack {
            Spacer()

            Button(action: {
                performMainPageAddAction()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))

                    Text(mainPageAddButtonTitle)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                }
                .foregroundColor(hubAccentButtonTextColor)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(hubAccentColor)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(mainPageAddButtonAccessibilityLabel)
        }
    }

    private func interactiveFolderSidebarOverlay(geometry: GeometryProxy) -> some View {
        InteractiveSidebarOverlay(
            isPresented: $showingFolderSidebar,
            canOpen: true,
            sidebarWidth: min(300, geometry.size.width * 0.82),
            colorScheme: colorScheme
        ) {
            FolderSidebarView(
                isPresented: $showingFolderSidebar,
                selectedFolderId: $selectedFolderId,
                showUnfiledNotesOnly: $showUnfiledNotesOnly
            )
        }
    }

    // MARK: - Tab Color Helpers

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return Color.appTextSecondary(colorScheme)
        }
    }

    private func tabBackgroundColor() -> Color {
        colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent
    }

    private func tabContainerColor() -> Color {
        Color.appChip(colorScheme)
    }

    private func tabContainerStrokeColor() -> Color {
        Color.appBorder(colorScheme)
    }

    // MARK: - Searchable Protocol

    func getSearchableContent() -> [SearchableItem] {
        var items: [SearchableItem] = []

        // Add main notes functionality
        items.append(SearchableItem(
            title: "Notes",
            content: "Create, edit, and organize your notes. Keep track of important thoughts and ideas.",
            type: .notes,
            identifier: "notes-main",
            metadata: ["category": "productivity"],
            tags: ["productivity", "notes", "organization"],
            date: Date()
        ))

        // Add notes content
        for note in notesManager.notes {
            let tags = extractTagsFromContent(note.content)
            let relatedNoteIds = detectCrossReferences(in: note, allNotes: notesManager.notes)

            items.append(SearchableItem(
                title: note.title,
                content: note.content,
                type: .notes,
                identifier: "note-\(note.id)",
                metadata: [
                    "isPinned": note.isPinned ? "true" : "false",
                    "dateModified": note.formattedDateModified,
                    "folder": notesManager.getFolderName(for: note.folderId)
                ],
                tags: tags,
                relatedItems: relatedNoteIds,
                date: note.dateModified
            ))
        }

        return items
    }

    /// Extract tags/categories from note content
    private func extractTagsFromContent(_ content: String) -> [String] {
        var tags: [String] = []
        let lowerContent = content.lowercased()

        // Define category keywords
        let categoryKeywords: [String: [String]] = [
            "finance": ["expense", "budget", "cost", "price", "bill", "payment", "invoice", "money", "dollar", "$", "amount", "total"],
            "health": ["doctor", "medical", "health", "prescription", "hospital", "clinic", "illness", "symptoms", "medicine"],
            "work": ["meeting", "project", "deadline", "client", "team", "work", "office", "business", "presentation"],
            "personal": ["family", "friend", "relationship", "personal", "home", "house", "apartment"],
            "travel": ["trip", "travel", "flight", "hotel", "destination", "vacation", "visit", "location", "address"],
            "shopping": ["store", "shop", "buy", "purchase", "order", "item", "product", "sale", "discount"],
            "food": ["recipe", "cook", "meal", "restaurant", "food", "eat", "ingredient", "cuisine", "dish"]
        ]

        // Check for category keywords
        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if lowerContent.contains(keyword) {
                    if !tags.contains(category) {
                        tags.append(category)
                    }
                    break
                }
            }
        }

        // Extract hashtags if present
        let hashtagPattern = "#[a-zA-Z0-9_]+"
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let nsString = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if let range = Range(match.range, in: content) {
                    let hashtag = String(content[range]).lowercased().dropFirst() // Remove #
                    if !tags.contains(String(hashtag)) {
                        tags.append(String(hashtag))
                    }
                }
            }
        }

        return tags
    }

    /// Detect cross-references between notes (when one note mentions another)
    private func detectCrossReferences(in note: Note, allNotes: [Note]) -> [String] {
        var relatedIds: [String] = []
        let lowerContent = note.content.lowercased()

        // Check if this note mentions other note titles
        for otherNote in allNotes {
            guard otherNote.id != note.id else { continue }
            let lowerTitle = otherNote.title.lowercased()

            // Only check if title is meaningful (more than 2 chars)
            if lowerTitle.count > 2 && lowerContent.contains(lowerTitle) {
                relatedIds.append("note-\(otherNote.id)")
            }
        }

        return relatedIds
    }

}

// MARK: - Note Edit View

struct NoteEditView: View {
    let note: Note?
    @Binding var isPresented: Bool
    let initialFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var attachmentService = AttachmentService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var attributedContent: NSAttributedString = NSAttributedString()
    @State private var currentNoteId: UUID? = nil  // Track note ID for attachment uploads
    @State private var editingNote: Note? = nil  // Track the note being edited (can be updated when new note is created)
    @State private var isLockedInSession: Bool = false
    @State private var showingFaceIDPrompt: Bool = false
    @State private var undoHistory: [(title: String, content: String)] = []
    @State private var redoHistory: [(title: String, content: String)] = []
    @State private var noteIsLocked: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContentFocused: Bool
    @State private var selectedFolderId: UUID? = nil
    @State private var showingFolderPicker = false
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var isProcessingCleanup = false
    @State private var isProcessingSummarize = false
    @State private var isProcessingAddMore = false
    @State private var showingAddMorePrompt = false
    @State private var addMorePromptText = ""
    @State private var showingShareSheet = false
    @StateObject private var openAIService = GeminiService.shared
    @State private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    @State private var showingImagePicker = false
    @State private var showingCameraPicker = false
    @State private var showingFileImporter = false
    @State private var showingReceiptImagePicker = false
    @State private var showingFormattingBar = false
    @State private var showingReceiptCameraPicker = false
    @State private var imageAttachments: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var showingAttachmentsSheet = false
    @State private var selectedImageIndex: Int = 0
    @State private var isKeyboardVisible = false
    @State private var isProcessingReceipt = false
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var isGeneratingTitle = false
    @State private var reminderNoteTarget: Note? = nil

    // File attachment states
    @State private var attachment: NoteAttachment?
    @State private var extractedData: ExtractedData?
    @State private var showingExtractionSheet = false
    @State private var showingFilePreview = false
    @State private var filePreviewURL: URL?
    @State private var isProcessingFile = false

    // Recurring expense states
    @State private var showingRecurringExpenseForm = false
    @State private var createdRecurringExpense: RecurringExpense?
    
    // OPTIMIZATION: Debounced auto-save for text changes
    @State private var autoSaveTask: Task<Void, Never>?
    
    // Event detection states
    @State private var showingEventCreationPrompt = false
    @State private var detectedEventDate: Date?
    @State private var detectedEventTitle: String = ""
    @State private var detectedEventLocation: String = ""
    @State private var detectedEventDescription: String = ""
    @State private var detectedEventEndDate: Date = Date()
    @State private var detectedEventIsMultiDay: Bool = false
    @State private var detectedEventHasTime: Bool = true
    @State private var isParsingEventFromNote: Bool = false
    @State private var eventSelectedTagId: String? = nil
    @State private var eventReminder: ReminderTime = .fifteenMinutes
    @State private var eventIsRecurring: Bool = false
    @State private var eventRecurrenceFrequency: RecurrenceFrequency = .weekly
    @State private var eventCustomDays: Set<WeekDay> = []
    @State private var eventSelectedTime: Date = Date()
    @State private var eventSelectedEndTime: Date = Date().addingTimeInterval(3600)
    @State private var showingEventDatePicker: Bool = false
    @State private var showingEventEndDatePicker: Bool = false
    
    // Table insertion
    @State private var showingTablePicker = false
    
    // Swipe-to-go-back gesture state for smooth iOS Notes-like navigation
    @State private var swipeOffset: CGFloat = 0
    @GestureState private var isDragging: Bool = false

    var isAnyProcessing: Bool {
        isProcessingCleanup || isProcessingSummarize || isProcessingAddMore || isProcessingReceipt || isGeneratingTitle || isProcessingFile
    }

    private var backlinkNotes: [Note] {
        let currentId = editingNote?.id ?? note?.id ?? currentNoteId
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedTitle.count >= 3 else { return [] }

        return notesManager.notes
            .filter { other in
                guard other.id != currentId else { return false }
                return other.content.lowercased().contains(normalizedTitle)
            }
            .sorted { $0.dateModified > $1.dateModified }
            .prefix(4)
            .map { $0 }
    }

    private var outboundLinkedNotes: [Note] {
        let currentId = editingNote?.id ?? note?.id ?? currentNoteId
        let lowerContent = content.lowercased()
        guard !lowerContent.isEmpty else { return [] }

        return notesManager.notes
            .filter { other in
                guard other.id != currentId else { return false }
                let candidate = other.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard candidate.count >= 3 else { return false }
                return lowerContent.contains(candidate)
            }
            .sorted { $0.dateModified > $1.dateModified }
            .prefix(4)
            .map { $0 }
    }

    private var combinedLinkedNotes: [Note] {
        var seen = Set<UUID>()
        var merged: [Note] = []
        for note in backlinkNotes + outboundLinkedNotes {
            if !seen.contains(note.id) {
                seen.insert(note.id)
                merged.append(note)
            }
        }
        return merged
    }
    
    var eventCreationMessage: String {
        var message = "\"\(detectedEventTitle)\""
        if let date = detectedEventDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            message += "\n\(formatter.string(from: date))"
        }
        return message
    }

    init(note: Note?, isPresented: Binding<Bool>, initialFolderId: UUID? = nil) {
        self.note = note
        self._isPresented = isPresented
        self.initialFolderId = initialFolderId
    }

    var body: some View {
        ZStack {
            mainContentView
        }
        .offset(x: swipeOffset)
        .animation(nil, value: swipeOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    // Only allow right swipe from left edge (x < 50)
                    if value.startLocation.x < 50 && value.translation.width > 0 {
                        let raw = value.translation.width
                        let resisted = raw < 120 ? raw : 120 + (raw - 120) * 0.6
                        swipeOffset = min(resisted, UIScreen.main.bounds.width * 0.5)
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 90
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let shouldDismiss = value.startLocation.x < 50 && (value.translation.width > threshold || (value.translation.width > 40 && velocity > 200))
                    if shouldDismiss {
                        swipeOffset = 0
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            saveNoteAndDismiss()
                        }
                    } else {
                        swipeOffset = 0
                    }
                }
        )
        .navigationBarHidden(true)
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .interactiveDismissDisabled()
        .onAppear(perform: onAppearAction)
        .onDisappear(perform: onDisappearAction)
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(
                selectedFolderId: $selectedFolderId,
                isPresented: $showingFolderPicker
            )
            .presentationBg()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let noteToShare = note {
                ShareSheet(activityItems: ["\(noteToShare.title)\n\n\(noteToShare.content)"])
            } else {
                ShareSheet(activityItems: ["\(title)\n\n\(content)"])
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImages: Binding(
                get: { imageAttachments },
                set: { newImages in
                    for image in newImages {
                        if imageAttachments.count < 10 {
                            imageAttachments.append(image)
                        }
                    }
                }
            ))
        }
        .sheet(isPresented: $showingCameraPicker) {
            CameraPicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        imageAttachments.append(image)
                    }
                }
            ))
        }
        .sheet(isPresented: $showingReceiptImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        processReceiptImage(image)
                    }
                }
            ))
        }
        .sheet(isPresented: $showingReceiptCameraPicker) {
            CameraPicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        processReceiptImage(image)
                    }
                }
            ))
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            if selectedImageIndex < imageAttachments.count {
                ImageViewer(image: imageAttachments[selectedImageIndex], isPresented: $showingImageViewer)
            }
        }
        .sheet(isPresented: $showingAttachmentsSheet) {
            NavigationView {
                imageAttachmentsView
                    .navigationTitle("Attachments (\(imageAttachments.count))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingAttachmentsSheet = false
                            }
                        }
                    }
            }
            .presentationBg()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [
                .pdf,
                .image,
                .plainText,
                .commaSeparatedText,
                UTType(filenameExtension: "csv") ?? .plainText,
                UTType(filenameExtension: "xlsx") ?? .spreadsheet
            ],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    handleFileSelected(url)
                case .failure(let error):
                    print("❌ File picker error: \(error.localizedDescription)")
                }
            }
        )
        .sheet(isPresented: $showingExtractionSheet) {
            if let extractedData = extractedData {
                ExtractionDetailSheet(
                    extractedData: extractedData,
                    onSave: { updatedData in
                        Task {
                            await saveExtractedData(updatedData)
                        }
                    }
                )
                .presentationBg()
            }
        }
        .sheet(isPresented: $showingFilePreview) {
            if let fileURL = filePreviewURL {
                FilePreviewSheet(fileURL: fileURL)
                    .presentationBg()
            }
        }
        .sheet(isPresented: $showingRecurringExpenseForm) {
            RecurringExpenseForm { expense in
                createdRecurringExpense = expense
                // TODO: Save to database and display success message
                HapticManager.shared.buttonTap()
                print("Created recurring expense: \(expense.title)")
            }
            .presentationBg()
        }
        .sheet(item: $reminderNoteTarget) { note in
            NoteReminderSheet(
                note: note,
                onSave: { date, message in
                    saveReminderForNote(note, date: date, message: message)
                },
                onRemove: {
                    removeReminderFromNote(note)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTablePicker) {
            TableTemplatePickerSheet(isPresented: $showingTablePicker) { template in
                insertTable(from: template)
            }
            .presentationBg()
        }
        .alert("Add More Information", isPresented: $showingAddMorePrompt) {
            TextField("What would you like to add?", text: $addMorePromptText)
            Button("Cancel", role: .cancel) {
                addMorePromptText = ""
            }
            Button("Add") {
                if !addMorePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await addMoreToNoteWithAI(userRequest: addMorePromptText)
                    }
                }
            }
        } message: {
            Text("Describe what to add and Seline will append it with clean formatting.")
        }
        // Event creation sheet (triggered by calendar icon in note)
        .sheet(isPresented: $showingEventCreationPrompt) {
            eventCreationSheetContent
        }
        .alert("Authentication Failed", isPresented: $showingFaceIDPrompt) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                authenticateWithBiometricOrPasscode()
            }
        } message: {
            Text("Face ID or Touch ID authentication failed or is not available. Please try again.")
        }
        .overlay(alignment: .top) {
            // Receipt processing toast indicator
            if receiptProcessingState != .idle {
                VStack {
                    ReceiptProcessingToast(state: receiptProcessingState)
                        .padding(.top, 8)
                    Spacer()
                }
                .zIndex(1000)
            }
        }
    }

    private var mainContentView: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()
            
            // Shadow overlay during swipe – fades in as you drag for a natural “reveal” feel
            if swipeOffset > 0 {
                let shadowOpacity = Double(min(swipeOffset / 120, 1)) * 0.22
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(shadowOpacity),
                                    Color.black.opacity(shadowOpacity * 0.4),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 36)
                        .offset(x: -36)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Custom toolbar - fixed at top
                customToolbar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((colorScheme == .dark ? Color.black : Color.white))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                    .zIndex(2)

                // Scrollable content area - takes available space
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Note content
                        if !isLockedInSession {
                            noteContentView
                        } else {
                            lockedStateView
                        }
                        
                        // Processing indicator - inside scroll view
                        if isProcessingReceipt || isProcessingFile {
                            HStack {
                                ShadcnSpinner(size: .small)
                                if isProcessingFile {
                                    Text("Analyzing file...")
                                        .font(FontManager.geist(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                } else {
                                    Text("Analyzing receipt...")
                                        .font(FontManager.geist(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        }
                        
                        // Bottom padding to ensure content is scrollable above keyboard
                        Color.clear
                            .frame(height: isLockedInSession ? 24 : 200)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 4)
                }
                .scrollDismissesKeyboard(.immediately)
                // Removed swipe-to-dismiss-keyboard gesture - it was interfering with normal typing
                // Users can dismiss keyboard by tapping outside the text field or using the keyboard dismiss key
                // Removed: Format bar no longer auto-dismisses when tapping content
                // User must manually tap the Aa button again to dismiss the formatting bar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLockedInSession {
                bottomActionButtons
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }


    // MARK: - View Components

    private var backgroundColor: some View {
        (colorScheme == .dark ? Color.black : Color.white)
    }

    private var customToolbar: some View {
        HStack(spacing: 12) {
            // Back button - no haptic needed for basic navigation
            Button(action: {
                saveNoteAndDismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Undo button - no haptic for common action
            Button(action: {
                undoLastChange()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }
            .disabled(undoHistory.isEmpty)
            .opacity(undoHistory.isEmpty ? 0.5 : 1.0)

            Spacer()

            // Share button - no haptic for common action
            Button(action: {
                showingShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Folder button - no haptic for common action
            Button(action: {
                showingFolderPicker = true
            }) {
                Image(systemName: "folder")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Delete button - keep haptic for destructive action
            Button(action: {
                HapticManager.shared.delete()
                deleteNote()
            }) {
                Image(systemName: "trash")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
            }
            .opacity(note != nil ? 1.0 : 0.5)
            .disabled(note == nil)

            // Lock/Unlock button - no haptic for toggle action
            Button(action: {
                toggleLock()
            }) {
                Image(systemName: noteIsLocked ? "lock.fill" : "lock.open")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Save button - keep haptic for important action
            Button(action: {
                HapticManager.shared.save()
                saveNoteAndDismiss()
            }) {
                Image(systemName: "checkmark")
                    .font(FontManager.geist(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            colorScheme == .dark ?
                                Color.white :
                                Color.black
                        )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 20)
    }
    
    // MARK: - Event Creation Sheet Content
    private var eventCreationSheetContent: some View {
        NavigationView {
            ScrollView {
                if isParsingEventFromNote {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Parsing event details...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    eventFormContent
                }
            }
            .navigationTitle("Create Event from Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingEventCreationPrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEventFromNote()
                    }
                    .disabled(detectedEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsingEventFromNote)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    // Separate computed property for the form to help compiler
    private var eventFormContent: some View {
        EventFormContent(
            title: $detectedEventTitle,
            location: $detectedEventLocation,
            description: $detectedEventDescription,
            selectedDate: Binding(
                get: { detectedEventDate ?? Date() },
                set: { detectedEventDate = $0 }
            ),
            selectedEndDate: $detectedEventEndDate,
            isMultiDay: $detectedEventIsMultiDay,
            hasTime: $detectedEventHasTime,
            selectedTime: $eventSelectedTime,
            selectedEndTime: $eventSelectedEndTime,
            isRecurring: $eventIsRecurring,
            recurrenceFrequency: $eventRecurrenceFrequency,
            customRecurrenceDays: $eventCustomDays,
            selectedReminder: $eventReminder,
            selectedTagId: $eventSelectedTagId,
            showingDatePicker: $showingEventDatePicker,
            showingEndDatePicker: $showingEventEndDatePicker
        )
    }

    private var noteContentView: some View {
        // Check if this note is in the Receipts folder or any subfolder of Receipts
        // Use note.folderId directly (the original parameter) as selectedFolderId/editingNote may not be set yet on first render
        let isReceiptNote: Bool = {
            guard let folderId = note?.folderId ?? selectedFolderId ?? editingNote?.folderId else { 
                return false 
            }
            let receiptsFolder = notesManager.folders.first(where: { $0.name == "Receipts" })
            guard let receiptsFolderId = receiptsFolder?.id else { 
                return false 
            }
            
            // Check if current folder is Receipts or a child of Receipts
            var currentId: UUID? = folderId
            while let id = currentId {
                if id == receiptsFolderId {
                    return true
                }
                // Check parent folder
                currentId = notesManager.folders.first(where: { $0.id == id })?.parentFolderId
            }
            return false
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            // Title - NO multiline axis so Enter triggers submit properly
            // Auto-focus title when creating new note (like Apple Notes)
            NoteTitleField(
                text: $title,
                isFocused: $isTitleFocused,
                onEnterPressed: {
                    // Explicitly transfer focus from title -> body for reliable "Next" behavior.
                    isTitleFocused = false
                    DispatchQueue.main.async {
                        isContentFocused = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if !isContentFocused {
                            isContentFocused = true
                        }
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .onChange(of: title) { _ in
                // Save to undo history on title change
                saveToUndoHistory()
            }
            
            // Content editor with table support and date detection
            HybridNoteContentView(
                content: $content,
                isContentFocused: $isContentFocused,
                onEditingChanged: {
                    // Save to undo history on content change
                    saveToUndoHistory()
                },
                onDateDetected: { date, context in
                    // User tapped highlighted date - parse event details with LLM
                    detectedEventDate = date
                    detectedEventEndDate = date.addingTimeInterval(3600) // 1 hour default
                    eventSelectedTime = date // Set the time picker to detected time
                    eventSelectedEndTime = date.addingTimeInterval(3600)
                    detectedEventHasTime = true
                    isParsingEventFromNote = true
                    showingEventCreationPrompt = true
                    
                    Task {
                        await parseEventDetailsFromNote(context: context, date: date)
                    }
                },
                onTodoInsert: {
                    insertTodoAtCursor()
                },
                isReceiptNote: isReceiptNote
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)

            if !combinedLinkedNotes.isEmpty {
                backlinksSection
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }
            
            Spacer()
        }
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backlinks")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.58))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 6) {
                ForEach(combinedLinkedNotes, id: \.id) { linked in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(linked.title.isEmpty ? "Untitled Note" : linked.title)
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)

                            Text(referencePreview(for: linked))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.55))
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    )
                }
            }
        }
    }

    private func referencePreview(for note: Note) -> String {
        let cleaned = note.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return note.formattedDateModified
        }
        return cleaned.count > 90 ? String(cleaned.prefix(90)) + "..." : cleaned
    }
    
    // Insert a todo checkbox at the cursor position
    private func insertTodoAtCursor() {
        // Add todo at end of content or on new line
        if content.isEmpty {
            content = "- [ ] "
        } else if content.hasSuffix("\n") {
            content += "- [ ] "
        } else {
            content += "\n- [ ] "
        }
    }

    // Insert a table from template
    private func insertTable(from template: TableTemplate) {
        var tableMarkdown = ""
        
        // Build header row
        if let headerRow = template.rows.first {
            tableMarkdown += "| " + headerRow.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |\n"
            // Add separator row
            tableMarkdown += "|" + headerRow.map { _ in "---" }.joined(separator: "|") + "|\n"
        }
        
        // Add data rows
        for row in template.rows.dropFirst() {
            tableMarkdown += "| " + row.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |\n"
        }
        
        // Insert into content
        if content.isEmpty {
            content = tableMarkdown
        } else if content.hasSuffix("\n") {
            content += "\n" + tableMarkdown
        } else {
            content += "\n\n" + tableMarkdown
        }
        
        HapticManager.shared.success()
    }

    private var imageAttachmentsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Image attachments
                ForEach(imageAttachments.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        // Image
                        Image(uiImage: imageAttachments[index])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                selectedImageIndex = index
                                showingImageViewer = true
                            }

                        // Delete button
                        Button(action: {
                            imageAttachments.remove(at: index)
                            if imageAttachments.isEmpty && attachment == nil {
                                showingAttachmentsSheet = false
                            }
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                Text("Remove")
                                    .font(FontManager.geist(size: 14, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                    }
                }

                // File attachment
                if let attachment = attachment {
                    VStack(alignment: .leading, spacing: 8) {
                        // File chip as tappable item
                        FileChip(
                            attachment: attachment,
                            onTap: {
                                Task {
                                    if let extracted = try await AttachmentService.shared.loadExtractedData(for: attachment.id) {
                                        await MainActor.run {
                                            self.extractedData = extracted
                                            self.showingExtractionSheet = true
                                        }
                                    }
                                }
                            },
                            onDelete: {
                                Task {
                                    try await AttachmentService.shared.deleteAttachment(attachment)
                                    await MainActor.run {
                                        self.attachment = nil
                                        self.extractedData = nil
                                        if imageAttachments.isEmpty {
                                            showingAttachmentsSheet = false
                                        }
                                        HapticManager.shared.success()
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
        .background((colorScheme == .dark ? Color.black : Color.white))
    }

    private var lockedStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(FontManager.geist(size: 48, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                Text("Note is locked")
                    .font(FontManager.geist(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                VStack(spacing: 12) {
                    Button(action: {
                        authenticateWithBiometricOrPasscode()
                    }) {
                        Text("Unlock with Face ID or Passcode")
                            .font(FontManager.geist(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                            )
                    }

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(FontManager.geist(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            )
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Apple Notes Style Floating Pill Toolbar
    private var bottomActionButtons: some View {
        VStack(spacing: 8) {
            if showingFormattingBar {
                formattingPillBar
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        HapticManager.shared.buttonTap()
                        showingFileImporter = true
                    } label: {
                        Label("Attach File", systemImage: "doc")
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        showingImagePicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo")
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        showingCameraPicker = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }

                    if !imageAttachments.isEmpty || attachment != nil {
                        Divider()
                        Button {
                            HapticManager.shared.buttonTap()
                            openAttachmentPreview()
                        } label: {
                            Label("View Attachments", systemImage: "eye")
                        }
                    }
                } label: {
                    sleekPrimaryActionIcon(systemName: "paperclip")
                }

                Button {
                    HapticManager.shared.buttonTap()
                    presentReminderSheet()
                } label: {
                    sleekPrimaryActionIcon(
                        systemName: currentReminderDate != nil ? "bell.badge.fill" : "bell.badge",
                        isActive: currentReminderDate != nil
                    )
                }
                .disabled(!canPresentReminderSheet)
                .opacity(canPresentReminderSheet ? 1 : 0.55)

                Menu {
                    Button {
                        HapticManager.shared.aiActionStart()
                        Task { await cleanUpNoteWithAI() }
                    } label: {
                        Label("Clean up", systemImage: "sparkles")
                    }
                    .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        HapticManager.shared.aiActionStart()
                        Task { await summarizeNoteWithAI() }
                    } label: {
                        Label("Summarize", systemImage: "text.bubble")
                    }
                    .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        HapticManager.shared.aiActionStart()
                        showingAddMorePrompt = true
                    } label: {
                        Label("Add More", systemImage: "plus.circle")
                    }
                    .disabled(isAnyProcessing)
                } label: {
                    sleekPrimaryActionIcon(systemName: "sparkles")
                }
                .opacity(isAnyProcessing ? 0.6 : 1)

                Menu {
                    Button {
                        HapticManager.shared.selection()
                        withAnimation {
                            showingFormattingBar.toggle()
                        }
                    } label: {
                        Label(showingFormattingBar ? "Hide Formatting" : "Show Formatting", systemImage: "textformat.size")
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        insertTodoAtCursor()
                    } label: {
                        Label("Insert Checklist", systemImage: "checklist")
                    }

                    Button {
                        HapticManager.shared.buttonTap()
                        showingTablePicker = true
                    } label: {
                        Label("Insert Table", systemImage: "tablecells")
                    }

                    Divider()

                    Button {
                        HapticManager.shared.buttonTap()
                        showingFolderPicker = true
                    } label: {
                        Label("Move Folder", systemImage: "folder")
                    }

                    Button {
                        HapticManager.shared.selection()
                        toggleLock()
                    } label: {
                        Label(noteIsLocked ? "Unlock Note" : "Lock Note", systemImage: noteIsLocked ? "lock.open" : "lock.fill")
                    }

                    if note != nil {
                        Divider()
                        Button(role: .destructive) {
                            HapticManager.shared.delete()
                            deleteNote()
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }

                    Divider()
                    Button {
                        HapticManager.shared.save()
                        saveNoteAndDismiss()
                    } label: {
                        Label("Save and Close", systemImage: "checkmark")
                    }
                } label: {
                    sleekPrimaryActionIcon(systemName: "ellipsis")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(sleekBottomBarBackground)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingFormattingBar)
    }

    private var sleekBottomBarBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.62),
                            colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.34)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private func sleekPrimaryActionIcon(systemName: String, isActive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.88))
            .frame(width: 40, height: 36)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.13))
                            : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
            )
            .overlay(
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
            )
    }

    private var canShareNote: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty || !trimmedContent.isEmpty || !imageAttachments.isEmpty
    }

    private var canPresentReminderSheet: Bool {
        canShareNote || editingNote != nil
    }

    private var currentReminderDate: Date? {
        reminderNoteTarget?.reminderDate ?? editingNote?.reminderDate ?? note?.reminderDate
    }

    @MainActor
    private func presentReminderSheet() {
        Task { @MainActor in
            guard let target = await ensureReminderTargetNote() else { return }
            reminderNoteTarget = target
        }
    }

    @MainActor
    private func ensureReminderTargetNote() async -> Note? {
        if let existing = editingNote {
            var noteWithCurrentText = existing
            noteWithCurrentText.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing.title : title.trimmingCharacters(in: .whitespacesAndNewlines)
            noteWithCurrentText.content = content
            return noteWithCurrentText
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty || !imageAttachments.isEmpty else { return nil }

        let finalTitle = trimmedTitle.isEmpty ? "Note" : trimmedTitle
        _ = await performSaveInBackground(title: finalTitle, content: content)
        return editingNote
    }

    private func saveReminderForNote(_ note: Note, date: Date, message: String) {
        var updatedNote = note
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedNote.title = trimmedTitle.isEmpty ? "Note" : trimmedTitle
        updatedNote.content = content
        updatedNote.reminderDate = date
        updatedNote.reminderNote = message.isEmpty ? nil : message
        updatedNote.dateModified = Date()
        notesManager.updateNote(updatedNote)
        editingNote = updatedNote
        reminderNoteTarget = updatedNote
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.upcomingNoteReminders)
        HapticManager.shared.success()
    }

    private func removeReminderFromNote(_ note: Note) {
        var updatedNote = note
        updatedNote.reminderDate = nil
        updatedNote.reminderNote = nil
        updatedNote.dateModified = Date()
        notesManager.updateNote(updatedNote)
        editingNote = updatedNote
        reminderNoteTarget = updatedNote
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.upcomingNoteReminders)
        HapticManager.shared.success()
    }

    private func openAttachmentPreview() {
        if !imageAttachments.isEmpty {
            showingAttachmentsSheet = true
            return
        }

        guard let att = attachment else { return }
        Task {
            if let data = try? await AttachmentService.shared.downloadFile(from: att.storagePath) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(att.fileName)
                try? data.write(to: tmp)
                await MainActor.run {
                    filePreviewURL = tmp
                    showingFilePreview = true
                }
            }
        }
    }
    
    // Formatting options pill with glass effect - Order: Body, H1, H2, H3, Bold, Italic, Strikethrough, Bullet, Numbered
    private var formattingPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                // Headings group
                formatIconButton(label: "Aa", size: 15) { applyFormattingActionAndDismiss(.body) }
                formatIconButton(label: "H1", size: 14, weight: .bold) { applyFormattingActionAndDismiss(.heading1) }
                formatIconButton(label: "H2", size: 13, weight: .semibold) { applyFormattingActionAndDismiss(.heading2) }
                formatIconButton(label: "H3", size: 12, weight: .medium) { applyFormattingActionAndDismiss(.heading3) }

                pillDivider

                // Text styling group
                formatIconButton(label: "B", size: 16, weight: .bold) { applyFormattingActionAndDismiss(.bold) }
                formatIconButton(label: "I", size: 16, isItalic: true) { applyFormattingActionAndDismiss(.italic) }
                formatStrikethroughButton { applyFormattingActionAndDismiss(.strikethrough) }

                pillDivider

                // List group
                formatSystemIconButton(systemName: "list.bullet") { applyFormattingActionAndDismiss(.bulletPoint) }
                formatSystemIconButton(systemName: "list.number") { applyFormattingActionAndDismiss(.numberedList) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(height: 50)
        .background(
            // Glassmorphism effect
            ZStack {
                // Blur background
                RoundedRectangle(cornerRadius: 26)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay for premium look
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.6),
                                colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.3)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Border for definition
                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    private func formatIconButton(label: String, size: CGFloat, weight: Font.Weight = .regular, isItalic: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Text(label)
                .font(isItalic ? .system(size: size, weight: weight).italic() : .system(size: size, weight: weight))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                .frame(width: 38, height: 34)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func formatStrikethroughButton(action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Text("S")
                .font(.system(size: 16, weight: .medium))
                .strikethrough(true)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                .frame(width: 38, height: 34)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func formatSystemIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                .frame(width: 38, height: 34)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var formattingDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
            .frame(width: 1, height: 22)
    }
    
    private var pillDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
            .frame(width: 1, height: 18)
    }
    
    // Main toolbar pill with glass effect matching format bar
    private var mainToolbarPill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Aa - formatting
                mainToolbarIconButton(systemName: "textformat.size", isActive: showingFormattingBar) {
                    withAnimation { showingFormattingBar.toggle() }
                }
                
                // Checklist
                mainToolbarIconButton(systemName: "checklist") { insertTodoAtCursor() }
                
                // Table
                mainToolbarIconButton(systemName: "tablecells") { showingTablePicker = true }
                
                // Attachment
                mainToolbarIconButton(systemName: "paperclip") { showingFileImporter = true }
                
                // Camera
                mainToolbarIconButton(systemName: "camera") { showingCameraPicker = true }
                
                // Photos
                mainToolbarIconButton(systemName: "photo") { showingImagePicker = true }
                
                // AI wand
                Menu {
                    Button { HapticManager.shared.aiActionStart(); Task { await cleanUpNoteWithAI() } } label: {
                        Label("Clean up", systemImage: "sparkles")
                    }
                    .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button { HapticManager.shared.aiActionStart(); Task { await summarizeNoteWithAI() } } label: {
                        Label("Summarize", systemImage: "text.bubble")
                    }
                    .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button { HapticManager.shared.aiActionStart(); showingAddMorePrompt = true } label: {
                        Label("Add More", systemImage: "plus.circle")
                    }
                    .disabled(isAnyProcessing)
                } label: {
                    Group {
                        if isProcessingCleanup || isProcessingSummarize || isProcessingAddMore {
                            ShadcnSpinner(size: .small)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 17))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    .frame(width: 42, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                }
                
                // Attachments badge
                if !imageAttachments.isEmpty || attachment != nil {
                    Button {
                        HapticManager.shared.buttonTap()
                        if !imageAttachments.isEmpty {
                            showingAttachmentsSheet = true
                        } else if let att = attachment {
                            Task {
                                if let data = try? await AttachmentService.shared.downloadFile(from: att.storagePath) {
                                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(att.fileName)
                                    try? data.write(to: tmp)
                                    await MainActor.run { filePreviewURL = tmp; showingFilePreview = true }
                                }
                            }
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "eye")
                                .font(.system(size: 17))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 42, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                            
                            Text("\(imageAttachments.count + (attachment != nil ? 1 : 0))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.red))
                                .offset(x: 4, y: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 52)
        .background(
            // Glassmorphism effect matching format bar
            ZStack {
                // Blur background
                RoundedRectangle(cornerRadius: 26)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay for premium look
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.6),
                                colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.3)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Border for definition
                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    private func mainToolbarIconButton(systemName: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.buttonTap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                .frame(width: 38, height: 34)
                .background(
                    Capsule()
                        .fill(
                            isActive
                                ? (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 0.5)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func applyFormattingAction(_ action: NoteFormattingAction) {
        NotificationCenter.default.post(
            name: .noteFormattingAction,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }
    
    private func applyFormattingActionAndDismiss(_ action: NoteFormattingAction) {
        applyFormattingAction(action)
        // Keep formatting bar visible - user must manually dismiss by tapping Aa button again
        // This allows rapid formatting without repeatedly opening the bar
    }

    // MARK: - Lifecycle Methods

    private func onAppearAction() {
        // Track that a note is being viewed (for tab bar visibility)
        notesManager.isViewingNoteInNavigation = true

        // Initialize editing note from parameter (or nil if creating new note)
        editingNote = note

        // Add keyboard observers
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            isKeyboardVisible = true
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            isKeyboardVisible = false
        }

        if let note = note {
            currentNoteId = note.id  // Track note ID for attachment uploads
            title = note.title
            content = note.content

            // Parse content and load images - defer to avoid layout glitches
            DispatchQueue.main.async {
                self.attributedContent = self.parseContentWithImages(note.content)
            }

            // Load images from URLs using ImageCacheManager (lazy loading)
            Task {
                var loadedImages: [UIImage] = []
                for imageUrl in note.imageUrls {
                    if let image = await ImageCacheManager.shared.getImage(url: imageUrl) {
                        loadedImages.append(image)
                    }
                }
                await MainActor.run {
                    self.imageAttachments = loadedImages
                }
            }

            // Load file attachment if it exists
            if let attachmentId = note.attachmentId {
                Task {
                    do {
                        try await AttachmentService.shared.loadAttachmentsForNote(note.id)
                        if let attachments = try await AttachmentService.shared.attachments.first {
                            await MainActor.run {
                                self.attachment = attachments
                            }
                        }
                    } catch {
                        print("Error loading attachment: \(error.localizedDescription)")
                    }
                }
            }

            noteIsLocked = note.isLocked
            selectedFolderId = note.folderId

            // If note is locked, require Face ID or Passcode to unlock
            if note.isLocked {
                isLockedInSession = true
                authenticateWithBiometricOrPasscode()
            }
        } else if let folderId = initialFolderId {
            // Set initial folder for new note
            selectedFolderId = folderId
        }
        
        // Auto-focus title when creating new note (like Apple Notes)
        // Use multiple attempts to ensure keyboard appears reliably
        if note == nil {
            // First attempt after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTitleFocused = true
            }
            // Second attempt to ensure keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !isTitleFocused {
                    isTitleFocused = true
                }
            }
        }

        // Initialize undo history
        saveToUndoHistory()
    }

    private func onDisappearAction() {
        // Clear the flag when note view disappears
        notesManager.isViewingNoteInNavigation = false

        // Notes are only saved explicitly via save button or swipe down
        // No auto-save on disappear
    }

    // MARK: - Actions

    private func saveNoteAndDismiss() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use content directly - UnifiedNoteEditor already stores as string
        let contentToSave = content
        let trimmedContent = contentToSave.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save completely empty notes
        guard !trimmedContent.isEmpty || !trimmedTitle.isEmpty || !imageAttachments.isEmpty else {
            dismiss()
            return
        }

        // PERFORMANCE FIX: Dismiss IMMEDIATELY - save in background
        // This eliminates any lag the user feels
        dismiss()
        
        // Simple save - no AI title generation (like Apple Notes)
        // If title is empty, use "Note" as fallback
        let finalTitle = trimmedTitle.isEmpty ? "Note" : trimmedTitle
        
        // Save in background - don't wait
        Task.detached(priority: .background) {
            await performSaveInBackground(title: finalTitle, content: contentToSave)
        }
    }
    
    /// Background save that doesn't block the UI
    @MainActor
    private func performSaveInBackground(title: String, content: String) async -> UUID? {
        return await performSave(title: title, content: content)
    }
    

    private func performSave(title: String, content: String) async -> UUID? {
        if let existingNote = editingNote {
            // Updating an existing note
            var updatedNote = existingNote
            updatedNote.title = title
            updatedNote.content = content
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            updatedNote.dateModified = Date()

            // Check if there are new images to upload (compare count)
            if imageAttachments.count > existingNote.imageUrls.count {
                // Upload images first, then update note with image URLs
                let newImages = Array(imageAttachments.suffix(imageAttachments.count - existingNote.imageUrls.count))
                let newImageUrls = await notesManager.uploadNoteImages(newImages, noteId: existingNote.id)
                updatedNote.imageUrls = existingNote.imageUrls + newImageUrls
                updatedNote.dateModified = Date()
            }

            // CRITICAL FIX: Call updateNote ONLY ONCE (it handles both UI update and background sync)
            // The duplicate call was causing race conditions and save failures
            notesManager.updateNote(updatedNote)
            editingNote = updatedNote
            return updatedNote.id
        } else {
            // Create new note - Use addNoteAndWaitForSync which handles both UI update and sync
            var newNote = Note(title: title, content: content, folderId: selectedFolderId)
            newNote.isLocked = noteIsLocked
            
            // CRITICAL FIX: Use ONLY addNoteAndWaitForSync (it adds to UI AND syncs)
            // Do NOT call addNote() separately - that causes duplicates!
            let syncSuccess = await notesManager.addNoteAndWaitForSync(newNote)
            editingNote = newNote
            
            if syncSuccess && !imageAttachments.isEmpty {
                // Upload images after note is synced (RLS policy requires note to exist first)
                let imageUrls = await notesManager.uploadNoteImages(imageAttachments, noteId: newNote.id)
                var updatedNote = newNote
                updatedNote.imageUrls = imageUrls
                updatedNote.dateModified = Date()
                // CRITICAL FIX: Use updateNoteAndWaitForSync to ensure images are saved
                let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
            } else if !syncSuccess {
                print("⚠️ Failed to sync note to Supabase, will retry on next save")
            }
            
            return newNote.id
        }
    }
    
    // OPTIMIZATION: Auto-save function for debounced text changes
    @MainActor
    private func performAutoSave() async {
        guard let existingNote = editingNote else { return }
        
        var updatedNote = existingNote
        updatedNote.title = title
        updatedNote.content = content
        updatedNote.dateModified = Date()
        
        // CRITICAL FIX: Call updateNote ONLY ONCE (it handles both UI update and background sync)
        // The duplicate call was causing race conditions
        notesManager.updateNote(updatedNote)
        editingNote = updatedNote
    }

    // Save note immediately when tables are updated (without dismissing)
    private func saveNoteImmediately() {
        guard let existingNote = note else { return }

        Task {
            var updatedNote = existingNote
            updatedNote.title = title.isEmpty ? "Untitled" : title
            updatedNote.content = content // Use content directly
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            updatedNote.imageUrls = existingNote.imageUrls // Keep existing image URLs

            // CRITICAL: Wait for sync to complete to ensure changes are persisted
            updatedNote.dateModified = Date()
            let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
        }
    }

    private func convertAttributedContentToText() -> String {
        // Convert NSAttributedString to Markdown to preserve formatting (bold, italic, headings)
        // Table and todo markers are also preserved in the conversion
        // The markers will be hidden in the UI by the RichTextEditor's hideMarkers() function
        // Use baseFontSize of 14 to match what parseContentWithImages uses (fontSize: 14)
        let markdown = AttributedStringToMarkdown.shared.convertToMarkdown(attributedContent, baseFontSize: 14)
        return markdown
    }


    private func deleteNote() {
        guard let note = note else { return }
        notesManager.deleteNote(note)
        dismiss()
    }

    private func toggleLock() {
        noteIsLocked.toggle()
    }

    private func authenticateWithBiometricOrPasscode() {
        let context = LAContext()
        var error: NSError?

        // Check if device owner authentication is available (biometric or passcode)
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Unlock your note"

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isLockedInSession = false
                    } else {
                        // Authentication failed
                        if let authError = authenticationError {
                            print("Authentication error: \(authError.localizedDescription)")
                        }
                        // Don't auto-dismiss, let user try again
                    }
                }
            }
        } else {
            // No authentication available at all
            print("Device authentication not available")
            showingFaceIDPrompt = true
        }
    }

    private func saveToUndoHistory() {
        // Track title and content as strings (like Notes app)
        let currentState = (title: title, content: content)
        
        // Only save if different from last state
        if let last = undoHistory.last, 
           last.title == currentState.title && last.content == currentState.content {
            return // No change, don't add to history
        }
        
        undoHistory.append(currentState)
        if undoHistory.count > 50 { // Limit history (increased for better undo support)
            undoHistory.removeFirst()
        }
        redoHistory.removeAll() // Clear redo when new changes are made
    }

    private func undoLastChange() {
        guard undoHistory.count > 1 else { return }

        let currentState = undoHistory.removeLast()
        redoHistory.append(currentState)

        if let previousState = undoHistory.last {
            title = previousState.title
            content = previousState.content
            // Update attributedContent from the new content string
            attributedContent = parseContentWithImages(previousState.content)
        }
    }

    // MARK: - Image Parsing

    private func parseContentWithImages(_ content: String) -> NSAttributedString {
        // Check if content is RTF-encoded (legacy format - for backwards compatibility)
        if content.hasPrefix("[RTF_CONTENT]") {
            let base64String = String(content.dropFirst("[RTF_CONTENT]".count))

            // Decode base64 to get RTF data
            if let rtfData = Data(base64Encoded: base64String),
               let attributedString = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
               ) {
                // Successfully loaded RTF content with formatting
                return attributedString
            } else {
                // RTF parsing failed - strip the marker and use plain text
                let plainContent = String(content.dropFirst("[RTF_CONTENT]".count))
                return NSAttributedString(
                    string: plainContent,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                        .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                    ]
                )
            }
        }

        // New format: Markdown with table/todo markers (markers are hidden by RichTextEditor)
        // Parse the markdown to restore formatting like bold, italic, headings, etc.
        let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
        return MarkdownParser.shared.parseMarkdown(content, fontSize: 14, textColor: textColor)
    }

    // MARK: - AI-Powered Text Editing

    private func cleanUpNoteWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingCleanup = true
        saveToUndoHistory()

        do {
            // Get cleaned text from AI (now returns markdown-formatted text)
            let aiCleanedText = try await openAIService.cleanUpNoteText(content)

            await MainActor.run {
                content = aiCleanedText
                // Parse markdown formatting (bold, italic, headings, etc)
                let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
                attributedContent = MarkdownParser.shared.parseMarkdown(aiCleanedText, fontSize: 14, textColor: textColor)
                isProcessingCleanup = false
                HapticManager.shared.aiActionComplete()
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingCleanup = false
                HapticManager.shared.error()
                print("Error cleaning up text: \(error.localizedDescription)")
            }
        }
    }

    private func summarizeNoteWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingSummarize = true
        saveToUndoHistory()

        do {
            // Get summarized text (now returns markdown-formatted text)
            let summarizedText = try await openAIService.summarizeNoteText(content)

            await MainActor.run {
                content = summarizedText
                // Parse markdown formatting (bold, italic, headings, etc)
                let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
                attributedContent = MarkdownParser.shared.parseMarkdown(summarizedText, fontSize: 14, textColor: textColor)
                isProcessingSummarize = false
                HapticManager.shared.aiActionComplete()
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingSummarize = false
                HapticManager.shared.error()
                print("Error summarizing text: \(error.localizedDescription)")
            }
        }
    }

    private func addMoreToNoteWithAI(userRequest: String) async {
        guard !userRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingAddMore = true
        saveToUndoHistory()

        do {
            // Get expanded text from AI
            let aiResponse = try await openAIService.addMoreToNoteText(content, userRequest: userRequest)
            let formattedOutput = normalizeAIAddMoreOutput(aiResponse)

            await MainActor.run {
                // Always append to keep user-authored note content intact.
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content = formattedOutput
                } else {
                    let separator: String
                    if content.hasSuffix("\n\n") {
                        separator = ""
                    } else if content.hasSuffix("\n") {
                        separator = "\n"
                    } else {
                        separator = "\n\n"
                    }
                    content += separator + formattedOutput
                }

                let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
                attributedContent = MarkdownParser.shared.parseMarkdown(content, fontSize: 14, textColor: textColor)
                isProcessingAddMore = false
                addMorePromptText = ""
                HapticManager.shared.aiActionComplete()
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingAddMore = false
                HapticManager.shared.error()
                print("Error adding more to text: \(error.localizedDescription)")
            }
        }
    }

    private func normalizeAIAddMoreOutput(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding markdown code fences while preserving markdown content inside.
        let lines = normalized.components(separatedBy: "\n")
        if lines.count >= 2,
           lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true,
           lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            normalized = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
    }
    
    // Event detection from note content
    private func detectEventFromContent() {
        guard content.count > 10 else { return }
        guard !showingEventCreationPrompt else { return }
        
        Task {
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let matches = detector.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
                
                if let match = matches.first, let date = match.date {
                    // Only prompt for future dates or today
                    if date >= Calendar.current.startOfDay(for: Date()) {
                        await MainActor.run {
                            self.detectedEventDate = date
                            // Extract context around the date
                            let range = Range(match.range, in: content) ?? content.startIndex..<content.endIndex
                            let lineStart = content[..<range.lowerBound].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
                            let lineEnd = content[range.upperBound...].firstIndex(of: "\n") ?? content.endIndex
                            self.detectedEventTitle = String(content[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                            self.showingEventCreationPrompt = true
                        }
                    }
                }
            }
        }
    }
    
    // Save event to Supabase via TaskManager
    private func saveEventToSupabase(title: String, date: Date, endDate: Date?, description: String) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        
        // Convert to WeekDay enum
        let dayOfWeek: WeekDay
        switch weekday {
        case 1: dayOfWeek = .sunday
        case 2: dayOfWeek = .monday
        case 3: dayOfWeek = .tuesday
        case 4: dayOfWeek = .wednesday
        case 5: dayOfWeek = .thursday
        case 6: dayOfWeek = .friday
        case 7: dayOfWeek = .saturday
        default: dayOfWeek = .monday
        }
        
        // Add task to TaskManager (saves to Supabase automatically)
        TaskManager.shared.addTask(
            title: title,
            to: dayOfWeek,
            description: description.isEmpty ? nil : description,
            scheduledTime: date,
            endTime: endDate,
            targetDate: date,
            reminderTime: .fifteenMinutes,
            isRecurring: false,
            recurrenceFrequency: nil,
            customRecurrenceDays: nil,
            tagId: nil
        )
        
        HapticManager.shared.success()
        showingEventCreationPrompt = false
    }
    
    // Parse event details from note context using LLM
    private func parseEventDetailsFromNote(context: String, date: Date) async {
        do {
            // Build a comprehensive prompt for the LLM to extract event details
            let prompt = """
            You are an intelligent event parser. Extract event details from this text and generate helpful context.
            
            Text: "\(context)"
            Detected base date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
            
            IMPORTANT RULES:
            1. The TITLE should NOT include the date/time - extract only the action or subject
            2. ALWAYS generate a brief, helpful description (1-3 sentences max)
            
            Extract and return JSON with these fields:
            - title: Clean EVENT NAME only. Remove any date/time. Capitalize properly. Examples:
              * "Jan 15 5pm - look into Lasic surgery" → "LASIK Surgery Research"
              * "tomorrow at 2pm meeting with John" → "Meeting with John"
              * "next week dentist appointment" → "Dentist Appointment"
            - description: REQUIRED - A brief helpful snippet about the topic (1-3 sentences). Examples:
              * "LASIK Surgery": "Eye surgery that reshapes the cornea to correct vision. Consult with an ophthalmologist to discuss candidacy and recovery time."
              * "Dentist Appointment": "Remember to bring insurance card and arrive 10 min early. Mention any sensitivity or concerns."
              * "Meeting with John": "Prepare agenda and key discussion points beforehand."
            - startTime: Time in HH:mm 24-hour format if mentioned (e.g., "5pm" -> "17:00")
            - endTime: End time in HH:mm format if mentioned, otherwise null
            - location: Location if mentioned, otherwise null
            
            Return ONLY valid JSON, no explanations:
            {"title": "...", "description": "...", "startTime": "...", "endTime": null, "location": null}
            """
            
            let response = try await openAIService.generateNoteTitle(from: prompt)
            
            // Clean the response - remove markdown code blocks if present
            var cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanResponse.hasPrefix("```json") {
                cleanResponse = String(cleanResponse.dropFirst(7))
            }
            if cleanResponse.hasPrefix("```") {
                cleanResponse = String(cleanResponse.dropFirst(3))
            }
            if cleanResponse.hasSuffix("```") {
                cleanResponse = String(cleanResponse.dropLast(3))
            }
            cleanResponse = cleanResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to parse JSON response
            if let jsonData = cleanResponse.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                await MainActor.run {
                    // Title - should NOT contain the date
                    if let title = json["title"] as? String, !title.isEmpty {
                        detectedEventTitle = title
                    } else {
                        // Fallback: try to extract meaningful words (not date/time)
                        let filteredWords = extractNonDateWords(from: context)
                        detectedEventTitle = filteredWords.prefix(5).joined(separator: " ").capitalized
                    }
                    
                    // Description - AI-generated helpful content
                    if let desc = json["description"] as? String, !desc.isEmpty, desc != "null" {
                        detectedEventDescription = desc
                    } else {
                        // Fallback: generate a simple placeholder based on title
                        if !detectedEventTitle.isEmpty {
                            detectedEventDescription = "Reminder: \(detectedEventTitle)"
                        }
                    }
                    
                    // Parse time if present (but don't override if already set from chip)
                    let calendar = Calendar.current
                    if let startTimeStr = json["startTime"] as? String, !startTimeStr.isEmpty, startTimeStr != "null" {
                        let parts = startTimeStr.split(separator: ":")
                        if parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                            if let newDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                                detectedEventDate = newDate
                                eventSelectedTime = newDate
                            }
                            detectedEventHasTime = true
                        }
                    }
                    
                    if let endTimeStr = json["endTime"] as? String, !endTimeStr.isEmpty, endTimeStr != "null" {
                        let parts = endTimeStr.split(separator: ":")
                        if parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                            if let endDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
                                detectedEventEndDate = endDate
                                eventSelectedEndTime = endDate
                            }
                        }
                    } else if detectedEventHasTime {
                        // Default end time 1 hour after start
                        detectedEventEndDate = (detectedEventDate ?? date).addingTimeInterval(3600)
                        eventSelectedEndTime = detectedEventEndDate
                    }
                    
                    // Location
                    if let location = json["location"] as? String, !location.isEmpty, location != "null" {
                        detectedEventLocation = location
                    }
                    
                    // Default reminder
                    eventReminder = .fifteenMinutes
                    
                    isParsingEventFromNote = false
                }
            } else {
                // Fallback: use smart extraction
                await MainActor.run {
                    let filteredWords = extractNonDateWords(from: context)
                    let titleWords = filteredWords.prefix(5).joined(separator: " ").capitalized
                    detectedEventTitle = titleWords
                    detectedEventDescription = "Reminder: \(titleWords)"
                    isParsingEventFromNote = false
                }
            }
        } catch {
            // Fallback on error
            await MainActor.run {
                let filteredWords = extractNonDateWords(from: context)
                detectedEventTitle = filteredWords.prefix(5).joined(separator: " ").capitalized
                if filteredWords.count > 5 {
                    detectedEventDescription = filteredWords.dropFirst(5).joined(separator: " ")
                }
                isParsingEventFromNote = false
            }
        }
    }
    
    /// Helper to extract words that are not dates/times
    private func extractNonDateWords(from text: String) -> [String] {
        let words = text.split(separator: " ").map { String($0) }
        let dateTimePatterns = [
            "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "am", "pm", "at", "on", "tomorrow", "today", "next", "week"
        ]
        
        return words.filter { word in
            let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            // Skip if it's a date pattern or looks like a time (contains digits and : or am/pm)
            if dateTimePatterns.contains(lowercased) { return false }
            if lowercased.range(of: #"^\d+:?\d*$"#, options: .regularExpression) != nil { return false }
            if lowercased.range(of: #"^\d+(am|pm)$"#, options: .regularExpression) != nil { return false }
            return true
        }
    }
    
    // Save event from the full EventFormContent
    private func saveEventFromNote() {
        guard let date = detectedEventDate else { return }
        
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        
        let dayOfWeek: WeekDay
        switch weekday {
        case 1: dayOfWeek = .sunday
        case 2: dayOfWeek = .monday
        case 3: dayOfWeek = .tuesday
        case 4: dayOfWeek = .wednesday
        case 5: dayOfWeek = .thursday
        case 6: dayOfWeek = .friday
        case 7: dayOfWeek = .saturday
        default: dayOfWeek = .monday
        }
        
        TaskManager.shared.addTask(
            title: detectedEventTitle,
            to: dayOfWeek,
            description: detectedEventDescription.isEmpty ? nil : detectedEventDescription,
            scheduledTime: detectedEventHasTime ? date : nil,
            endTime: detectedEventHasTime ? detectedEventEndDate : nil,
            targetDate: date,
            reminderTime: eventReminder,
            location: detectedEventLocation.isEmpty ? nil : detectedEventLocation,
            isRecurring: eventIsRecurring,
            recurrenceFrequency: eventIsRecurring ? eventRecurrenceFrequency : nil,
            customRecurrenceDays: eventRecurrenceFrequency == .custom ? Array(eventCustomDays) : nil,
            tagId: eventSelectedTagId
        )
        
        HapticManager.shared.success()
        showingEventCreationPrompt = false
        
        // Reset state

        detectedEventTitle = ""
        detectedEventLocation = ""
        detectedEventDescription = ""
        detectedEventDate = nil
    }

    private func processReceiptImage(_ image: UIImage) {
        // Process with AI
        Task {
            isProcessingReceipt = true
            
            // Show processing indicator
            await MainActor.run {
                receiptProcessingState = .processing
            }

            do {
                let (receiptTitle, receiptContent) = try await openAIService.analyzeReceiptImage(image)

                // Clean up the extracted content - remove extra whitespace and format nicely
                let cleanedContent = receiptContent
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                // Extract month and year from receipt title for automatic folder organization
                var folderIdForReceipt: UUID?
                if let (month, year) = notesManager.extractMonthYearFromTitle(receiptTitle) {
                    // Use async folder creation to ensure folders sync before using IDs
                    folderIdForReceipt = await notesManager.getOrCreateReceiptMonthFolderAsync(month: month, year: year)
                    print("✅ Receipt assigned to \(notesManager.getMonthName(month)) \(year)")
                } else {
                    // Fallback to main Receipts folder if no date found
                    let receiptsFolderId = notesManager.getOrCreateReceiptsFolder()
                    folderIdForReceipt = receiptsFolderId
                    print("⚠️ No date found in receipt title, using main Receipts folder")
                }

                // Update UI state on main actor and capture values for saving
                let (finalTitle, finalContent) = await MainActor.run {
                    // Add the receipt image to attachments so it shows in the eye icon
                    imageAttachments.append(image)
                    print("✅ Receipt image added to attachments (total: \(imageAttachments.count))")

                    // Provide haptic feedback that image was captured
                    HapticManager.shared.success()

                    // Set title if empty or update it
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = receiptTitle
                    }

                    // Assign folder to receipt
                    if let folderId = folderIdForReceipt {
                        selectedFolderId = folderId
                    }

                    // Append cleaned receipt content to existing content
                    let newContent = content.isEmpty ? cleanedContent : content + "\n\n" + cleanedContent
                    content = newContent

                    // Convert markdown to attributed string
                    attributedContent = convertMarkdownToAttributedString(newContent)

                    isProcessingReceipt = false
                    saveToUndoHistory()
                    
                    // Return values for saving
                    return (title.isEmpty ? receiptTitle : title, newContent)
                }

                // Auto-save the note with the receipt image and cleaned content (async operation)
                await saveReceiptNoteWithImage(title: finalTitle, content: finalContent)

                // Auto-dismiss after saving completes
                await MainActor.run {
                    HapticManager.shared.success()
                    receiptProcessingState = .success
                    isProcessingReceipt = false
                    self.isPresented = false
                    
                    // Hide success message after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            receiptProcessingState = .idle
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessingReceipt = false
                    print("Error analyzing receipt: \(error.localizedDescription)")
                    receiptProcessingState = .error(error.localizedDescription)
                    HapticManager.shared.error()
                    
                    // Hide error message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            receiptProcessingState = .idle
                        }
                    }
                }
            }
        }
    }

    private func saveReceiptNoteWithImage(title: String, content: String) async {
        if let existingNote = note {
            // Updating an existing note
            var updatedNote = existingNote
            updatedNote.title = title
            updatedNote.content = content
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId

            // Upload new receipt images (compare count to find new ones)
            if imageAttachments.count > existingNote.imageUrls.count {
                let newImages = Array(imageAttachments.suffix(imageAttachments.count - existingNote.imageUrls.count))
                let newImageUrls = await notesManager.uploadNoteImages(newImages, noteId: existingNote.id)
                updatedNote.imageUrls = existingNote.imageUrls + newImageUrls
                print("✅ Receipt images uploaded and saved to Supabase")
            }

            updatedNote.dateModified = Date()
            let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
        } else {
            // Create new receipt note - MUST save to database first, then upload images
            var newNote = Note(title: title, content: content, folderId: selectedFolderId)
            newNote.isLocked = noteIsLocked

            // 1. Add note to database and WAIT for sync
            let syncSuccess = await notesManager.addNoteAndWaitForSync(newNote)

            if !syncSuccess {
                print("❌ Failed to sync receipt note to Supabase before uploading images")
                return
            }

            // 2. NOW upload images (RLS policy requires note to exist first)
            if !imageAttachments.isEmpty {
                let imageUrls = await notesManager.uploadNoteImages(imageAttachments, noteId: newNote.id)

                // 3. Update note with image URLs
                var updatedNote = newNote
                updatedNote.imageUrls = imageUrls
                updatedNote.dateModified = Date()
                let _ = await notesManager.updateNoteAndWaitForSync(updatedNote)
                print("✅ Receipt images uploaded to Supabase for new note")
            } else {
                print("✅ Receipt note saved without images")
            }
        }
    }

    private func convertMarkdownToAttributedString(_ text: String) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString()

        // Default attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
        ]

        // Split text into lines
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let currentLine = line
            let lineAttributedString = NSMutableAttributedString()
            var lastIndex = 0

            // Find all **text** patterns for bold
            let boldPattern = "\\*\\*([^*]+)\\*\\*"
            if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
                let matches = regex.matches(in: currentLine, options: [], range: NSRange(currentLine.startIndex..., in: currentLine))

                for match in matches {
                    // Add text before the match
                    if match.range.location > lastIndex {
                        let beforeRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                        if let range = Range(beforeRange, in: currentLine) {
                            let beforeText = String(currentLine[range])
                            lineAttributedString.append(NSAttributedString(string: beforeText, attributes: defaultAttributes))
                        }
                    }

                    // Add the bold text
                    if let range = Range(match.range(at: 1), in: currentLine) {
                        let boldText = String(currentLine[range])
                        let boldAttributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                        ]
                        lineAttributedString.append(NSAttributedString(string: boldText, attributes: boldAttributes))
                    }

                    lastIndex = match.range.location + match.range.length
                }

                // Add remaining text after last match
                if lastIndex < currentLine.count {
                    let remainingRange = NSRange(location: lastIndex, length: currentLine.count - lastIndex)
                    if let range = Range(remainingRange, in: currentLine) {
                        let remainingText = String(currentLine[range])
                        lineAttributedString.append(NSAttributedString(string: remainingText, attributes: defaultAttributes))
                    }
                }
            }

            // If no matches found, add the whole line with default attributes
            if lineAttributedString.length == 0 {
                lineAttributedString.append(NSAttributedString(string: currentLine, attributes: defaultAttributes))
            }

            // Add to main string
            mutableAttributedString.append(lineAttributedString)

            // Add newline if not last line
            if index < lines.count - 1 {
                // Add extra spacing before section headers for better readability
                let isNextLineHeader = (index + 1 < lines.count) &&
                    (lines[index + 1].contains("**Items") ||
                     lines[index + 1].contains("**Summary") ||
                     lines[index + 1].contains("**Payment") ||
                     lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("📍") ||
                     lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("💳"))

                let spacing = isNextLineHeader ? "\n\n" : "\n"
                mutableAttributedString.append(NSAttributedString(string: spacing, attributes: defaultAttributes))
            }
        }

        return mutableAttributedString
    }

    // MARK: - File Attachment Handling

    private func handleFileSelected(_ fileURL: URL) {
        Task {
            isProcessingFile = true

            defer {
                isProcessingFile = false
            }

            do {
                // Start accessing the security-scoped resource
                guard fileURL.startAccessingSecurityScopedResource() else {
                    print("❌ Cannot access file - permission denied")
                    await MainActor.run {
                        HapticManager.shared.error()
                    }
                    return
                }

                defer { fileURL.stopAccessingSecurityScopedResource() }

                // Get file data
                let fileData = try Data(contentsOf: fileURL)
                let fileName = fileURL.lastPathComponent

                print("📄 Processing file: \(fileName)")
                print("📄 File size: \(fileData.count) bytes")

                // Extract text from file
                let fileContent = extractTextFromFile(fileData, fileName: fileName)
                print("✅ Extracted \(fileContent.count) characters from file")

                // Detect document type
                let documentType = detectDocumentType(fileName)

                // Build extraction prompt
                let prompt = buildExtractionPrompt(fileName: fileName, documentType: documentType)

                // Call OpenAI to process the text
                print("🤖 Processing with OpenAI...")
                let openAIService = GeminiService.shared
                let processedText = try await openAIService.extractDetailedDocumentContent(
                    fileContent,
                    withPrompt: prompt,
                    fileName: fileName
                )

                print("✅ OpenAI processing complete")

                // Clean markdown symbols
                let cleanedText = cleanMarkdownSymbols(processedText)

                // Add to note body
                await MainActor.run {
                    if self.content.isEmpty {
                        self.content = cleanedText
                    } else {
                        self.content = self.content + "\n\n" + cleanedText
                    }

                    // Update attributed content
                    let newAttrString = NSMutableAttributedString(attributedString: self.attributedContent)
                    let textToAdd = NSAttributedString(
                        string: (self.attributedContent.length > 0 ? "\n\n" : "") + cleanedText,
                        attributes: [
                            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                            .foregroundColor: self.colorScheme == .dark ? UIColor.white : UIColor.black
                        ]
                    )
                    newAttrString.append(textToAdd)
                    self.attributedContent = newAttrString

                    print("✅ File content added to note")
                }

                // Upload file to Supabase Storage
                print("📤 Uploading file to Supabase...")

                // Ensure we have a note ID and save the note first if it's new
                // (RLS policy requires the note to exist before we can attach files)
                var noteIdForUpload: UUID?
                var shouldUpdateNote = false

                // Priority 1: If we're editing an existing note, ALWAYS use it (prevents duplication)
                if let existingNote = self.editingNote {
                    noteIdForUpload = existingNote.id
                    shouldUpdateNote = true
                    print("📝 Attaching file to existing note: \(existingNote.title)")
                }
                // Priority 2: If currentNoteId is set but we don't have self.note (edge case)
                else if let existingNoteId = self.currentNoteId {
                    noteIdForUpload = existingNoteId
                    shouldUpdateNote = true
                    print("📝 Attaching file to note: \(existingNoteId.uuidString)")
                }
                // Priority 3: Create a new note
                else {
                    var newNote = Note(title: self.title.isEmpty ? "Untitled" : self.title, content: self.content)
                    newNote.folderId = self.selectedFolderId

                    // Save to Supabase synchronously to ensure RLS passes for file attachment
                    let saved = await self.notesManager.addNoteAndWaitForSync(newNote)
                    if saved {
                        noteIdForUpload = newNote.id
                        shouldUpdateNote = true

                        // CRITICAL: Update editingNote so subsequent saves don't create duplicates
                        // This marks the note as "existing" in the local state
                        await MainActor.run {
                            self.editingNote = newNote
                        }

                        print("✅ New note created in Supabase: \(newNote.id.uuidString)")

                        // Increase delay significantly to ensure write propagation in Supabase
                        // This ensures the RLS policy can find the note when inserting the attachment
                        // (RLS policies need to SELECT from notes table to verify ownership)
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                        // Verify the note exists before proceeding with attachment
                        print("📋 Verifying note exists in database...")
                        do {
                            let client = await SupabaseManager.shared.getPostgrestClient()
                            let response: [NoteSupabaseData] = try await client
                                .from("notes")
                                .select()
                                .eq("id", value: newNote.id.uuidString)
                                .limit(1)
                                .execute()
                                .value

                            if response.isEmpty {
                                print("⚠️ Note saved but not yet visible in database. Trying again...")
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 more second
                            } else {
                                print("✅ Note verified in database")
                            }
                        } catch {
                            print("⚠️ Could not verify note: \(error). Proceeding anyway...")
                        }
                    } else {
                        print("❌ Failed to save new note to Supabase")
                        await MainActor.run {
                            HapticManager.shared.error()
                        }
                        return
                    }
                }

                guard let noteId = noteIdForUpload else {
                    print("❌ Failed to get note ID for file upload")
                    await MainActor.run {
                        HapticManager.shared.error()
                    }
                    return
                }

                // Determine file type from extension
                let fileExtension = (fileName as NSString).pathExtension.lowercased()
                var fileType = fileExtension
                if fileExtension == "pdf" {
                    fileType = "pdf"
                } else if ["csv", "tsv"].contains(fileExtension) {
                    fileType = "csv"
                } else if ["xlsx", "xls"].contains(fileExtension) {
                    fileType = "excel"
                } else if ["jpg", "jpeg", "png", "gif", "webp"].contains(fileExtension) {
                    fileType = "image"
                } else if fileExtension == "txt" {
                    fileType = "text"
                }

                do {
                    // Upload file to Supabase
                    let uploadedAttachment = try await self.attachmentService.uploadFileToNote(
                        fileData,
                        fileName: fileName,
                        fileType: fileType,
                        noteId: noteId
                    )

                    print("✅ File uploaded successfully: \(fileName)")

                    // Update note with attachment ID
                    if shouldUpdateNote {
                        var noteToUpdate: Note
                        if let existingNote = self.editingNote {
                            noteToUpdate = existingNote
                        } else {
                            // Recreate the note with updated content and attachment
                            noteToUpdate = Note(title: self.title.isEmpty ? "Untitled" : self.title, content: self.content)
                            noteToUpdate.id = noteId
                            noteToUpdate.folderId = self.selectedFolderId
                        }

                        noteToUpdate.attachmentId = uploadedAttachment.id

                        // Update the note synchronously to ensure file is linked
                        await self.notesManager.updateNoteAndWaitForSync(noteToUpdate)

                        // Update UI on main thread
                        await MainActor.run {
                            self.attachment = uploadedAttachment
                            // CRITICAL: Update editingNote to reflect the attachment
                            self.editingNote = noteToUpdate
                            HapticManager.shared.success()
                            print("✅ Note updated with attachment")
                        }
                    }

                } catch {
                    print("❌ File upload error: \(error.localizedDescription)")
                    await MainActor.run {
                        HapticManager.shared.error()
                    }
                }

            } catch {
                print("❌ File processing error: \(error.localizedDescription)")
                await MainActor.run {
                    HapticManager.shared.error()
                }
            }
        }
    }

    /// Extract text from file (moved from AttachmentService)
    private func extractTextFromFile(_ fileData: Data, fileName: String) -> String {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "txt", "csv", "json", "xml", "log":
            if let textContent = String(data: fileData, encoding: .utf8) {
                return textContent
            }
            if let textContent = String(data: fileData, encoding: .isoLatin1) {
                return textContent
            }
            return "[File could not be converted to text.]"

        case "pdf":
            if let pdfDocument = PDFDocument(data: fileData) {
                var extractedText = ""
                let pageCount = pdfDocument.pageCount

                for pageIndex in 0..<pageCount {
                    if let page = pdfDocument.page(at: pageIndex) {
                        if let pageText = page.string {
                            extractedText += "--- Page \(pageIndex + 1) ---\n"
                            extractedText += pageText
                            extractedText += "\n\n"
                        }
                    }
                }

                if !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return extractedText
                }
            }
            return "[PDF file found but contains no extractable text.]"

        default:
            if let textContent = String(data: fileData, encoding: .utf8) {
                let cleaned = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count > 20 {
                    return cleaned
                }
            }
            return "[File type not supported for text extraction.]"
        }
    }

    /// Clean markdown symbols (moved from AttachmentService)
    private func cleanMarkdownSymbols(_ text: String) -> String {
        var cleaned = text

        // Remove bold markers (**)
        cleaned = cleaned.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)

        // Remove italic markers (*) - but preserve asterisks in bullet lists
        cleaned = cleaned.replacingOccurrences(of: "\\*([^\\*\\n]+)\\*", with: "$1", options: .regularExpression)

        // Remove underscores used for formatting (__text__ or _text_)
        cleaned = cleaned.replacingOccurrences(of: "__+(.+?)__+", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "_([^_\\n]+)_", with: "$1", options: .regularExpression)

        // Remove heading markers (#) at start of lines
        cleaned = cleaned.split(separator: "\n").map { line in
            var trimmedLine = String(line)
            while trimmedLine.hasPrefix("#") {
                trimmedLine = String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return trimmedLine
        }.joined(separator: "\n")

        // Remove horizontal rule markers (multiple dashes/equals on their own line)
        cleaned = cleaned.split(separator: "\n").filter { line in
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            // Filter out lines that are just dashes, equals, or tildes
            return !(trimmed.allSatisfy { $0 == "-" || $0 == "=" || $0 == "~" } && trimmed.count > 2)
        }.joined(separator: "\n")

        // Remove backticks (code formatting)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")

        // Remove tilde strikethrough (~~text~~)
        cleaned = cleaned.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)

        // Fix multiple consecutive blank lines (replace 3+ newlines with 2)
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)

        // Remove trailing whitespace from each line but preserve single spaces
        cleaned = cleaned.split(separator: "\n").map { line in
            String(line).trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detect document type (moved from AttachmentService)
    private func detectDocumentType(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("bank") || lower.contains("statement") || lower.contains("account") {
            return "bank_statement"
        } else if lower.contains("invoice") || lower.contains("bill") {
            return "invoice"
        } else if lower.contains("receipt") || lower.contains("order") {
            return "receipt"
        }
        return "document"
    }

    /// Build extraction prompt (moved from AttachmentService)
    private func buildExtractionPrompt(fileName: String, documentType: String) -> String {
        return """
        Extract the raw text content from this file: \(fileName)

        Simply extract and preserve all substantive text content from the document. Do not summarize, condense, or modify the text. Keep the content as-is, maintaining its structure and organization.

        Remove only obvious non-content items like page numbers, headers/footers, and sensitive identifiers (account numbers, SSN, etc.), but preserve all actual document content.
        """
    }

    private func saveExtractedData(_ data: ExtractedData) async {
        do {
            try await AttachmentService.shared.updateExtractedData(data)
            await MainActor.run {
                self.extractedData = data
                HapticManager.shared.success()
            }
        } catch {
            print("❌ Error saving extracted data: \(error.localizedDescription)")
            HapticManager.shared.error()
        }
    }
}

// MARK: - Content Segment Types

/// Represents a segment of note content (either text or a table)
enum ContentSegment {
    case text(NSAttributedString)
    case table(UUID)

    var isTable: Bool {
        if case .table = self { return true }
        return false
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(FontManager.geist(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .padding()
                }

                Spacer()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()

                Spacer()
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Formatting Menu View

struct FormattingMenuView: View {
    @Binding var isPresented: Bool
    let colorScheme: ColorScheme
    let hasSelection: Bool
    let onInsertTable: () -> Void
    let onApplyFormatting: (TextFormat) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                List {
                    Section {
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onInsertTable()
                        }) {
                            HStack {
                                Image(systemName: "tablecells")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24)
                                Text("Insert Table")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }
                    } header: {
                        Text("Insert")
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }

                    Section {
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.bold)
                        }) {
                            HStack {
                                Image(systemName: "bold")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Bold")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)

                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.italic)
                        }) {
                            HStack {
                                Image(systemName: "italic")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Italic")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)

                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.underline)
                        }) {
                            HStack {
                                Image(systemName: "underline")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Underline")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)

                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.heading1)
                        }) {
                            HStack {
                                Image(systemName: "textformat.size.larger")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Heading 1")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)

                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.heading2)
                        }) {
                            HStack {
                                Image(systemName: "textformat.size")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Heading 2")
                                    .font(FontManager.geist(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)
                    } header: {
                        Text("Text Formatting")
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    } footer: {
                        if !hasSelection {
                            Text("Select text to apply formatting")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .scrollContentBackground(.hidden)
                .background((colorScheme == .dark ? Color.black : Color.white))
            }
            .navigationTitle("Formatting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color.white :
                            Color.black
                    )
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Custom Auto-Sizing TextView for Title
class AutoSizingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        // Ensure we have a valid width
        guard bounds.width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 32)
        }

        // Force layout to calculate correct size
        layoutManager.ensureLayout(for: textContainer)

        // Calculate the height needed for the current text
        let size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        let estimatedSize = sizeThatFits(size)

        // Ensure minimum height
        let finalHeight = max(estimatedSize.height, 32)

        return CGSize(width: UIView.noIntrinsicMetric, height: finalHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }

    override var bounds: CGRect {
        didSet {
            // When bounds change (width changes), invalidate size to recalculate height
            if oldValue.width != bounds.width {
                invalidateIntrinsicContentSize()
            }
        }
    }
}

// MARK: - Note Title Field (UIKit wrapper for proper Enter key handling)
// This ensures pressing Enter in title moves focus to body, NOT insert newline
// USES UITextView for text wrapping (UITextField doesn't support wrapping)
struct NoteTitleField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onEnterPressed: () -> Void

    func makeUIView(context: Context) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        textView.textColor = UIColor.label
        textView.backgroundColor = .clear
        textView.returnKeyType = .next
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // CRITICAL FIX: Enable text wrapping to prevent horizontal scrolling
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.maximumNumberOfLines = 0 // Allow multiple lines for long titles

        // Disable horizontal scrolling completely
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = false
        textView.bounces = false

        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // Set initial text or placeholder
        if text.isEmpty {
            textView.text = "Title"
            textView.textColor = UIColor.placeholderText
        } else {
            textView.text = text
            textView.textColor = UIColor.label
        }

        // Force initial layout
        textView.layoutIfNeeded()

        return textView
    }

    func updateUIView(_ textView: AutoSizingTextView, context: Context) {
        // Only update text if it changed externally
        if textView.text != text && !textView.isFirstResponder {
            if text.isEmpty {
                textView.text = "Title"
                textView.textColor = UIColor.placeholderText
            } else {
                textView.text = text
                textView.textColor = UIColor.label
            }
            // CRITICAL: Invalidate size after updating text
            textView.invalidateIntrinsicContentSize()
        }

        // Handle focus requests
        if isFocused.wrappedValue && !textView.isFirstResponder {
            // Use async to avoid SwiftUI state update conflicts
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTitleField

        init(_ parent: NoteTitleField) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Handle Enter key press - move to body field
            if text == "\n" {
                parent.isFocused.wrappedValue = false
                textView.resignFirstResponder()
                parent.onEnterPressed()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            // Keep placeholder handling in begin/end editing only.
            // Injecting placeholder during typing causes focus and cursor glitches.
            if textView.textColor == UIColor.placeholderText {
                return
            }

            // Update binding as user types
            parent.text = textView.text

            // CRITICAL: Force layout and invalidate size immediately
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            textView.invalidateIntrinsicContentSize()

            // Notify SwiftUI that layout needs to update
            DispatchQueue.main.async {
                textView.invalidateIntrinsicContentSize()
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Clear placeholder when user starts typing
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }

            DispatchQueue.main.async {
                self.parent.isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Show placeholder if empty
            if textView.text.isEmpty {
                textView.text = "Title"
                textView.textColor = UIColor.placeholderText
            }

            // Sync final text
            parent.text = textView.text == "Title" && textView.textColor == UIColor.placeholderText ? "" : textView.text

            DispatchQueue.main.async {
                self.parent.isFocused.wrappedValue = false
            }
        }
    }
}

// MARK: - Scale Button Style for elegant press feedback
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NotesView()
}
