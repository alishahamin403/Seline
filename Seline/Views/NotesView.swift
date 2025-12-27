import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers
import PDFKit

struct NotesView: View, Searchable {
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var showingNewNoteSheet = false
    @State private var selectedNote: Note? = nil
    @State private var navigationPath: [Note] = []
    @State private var isPinnedExpanded = true
    @State private var expandedSections: Set<String> = ["RECENT"]
    @State private var showingFolderSidebar = false
    @State private var selectedFolderId: UUID? = nil
    @State private var showReceiptStats = false
    @State private var showingRecurringExpenseForm = false
    @State private var selectedTab = "notes" // "notes", "receipts", "recurring"
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @StateObject private var openAIService = DeepSeekService.shared
    @Namespace private var tabAnimation
    @State private var receiptProcessingState: ReceiptProcessingState = .idle

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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header section with search
                    VStack(spacing: 0) {
                        // Pill tabs and icon buttons in same row
                        HStack(spacing: 12) {
                            // Folder button - only show in notes tab
                            if selectedTab == "notes" {
                                Button(action: {
                                    withAnimation {
                                        showingFolderSidebar.toggle()
                                    }
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            // Search button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isSearchActive {
                                        isSearchActive = false
                                        searchText = ""
                                    } else {
                                        isSearchActive = true
                                    }
                                }
                            }) {
                                Image(systemName: isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Spacer()

                            // Pill tabs - centered
                            HStack(spacing: 4) {
                                ForEach(["notes", "receipts", "recurring"], id: \.self) { tab in
                                    let isSelected = selectedTab == tab
                                    let tabIcon = tab == "notes" ? "note.text" : (tab == "receipts" ? "receipt.fill" : "repeat.circle.fill")

                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedTab = tab
                                            // Clear search when switching tabs
                                            searchText = ""
                                            selectedFolderId = nil
                                        }
                                    }) {
                                        Image(systemName: tabIcon)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(tabForegroundColor(isSelected: isSelected))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background {
                                                if isSelected {
                                                    Capsule()
                                                        .fill(tabBackgroundColor())
                                                        .matchedGeometryEffect(id: "tab", in: tabAnimation)
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
                            )

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                        // Search bar - show when search is active
                        if isSearchActive {
                            VStack(spacing: 0) {
                                EmailSearchBar(searchText: $searchText) { query in
                                    // Search is handled by filtering
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 0)
                                
                                // Search results dropdown
                                if !searchText.isEmpty {
                                    searchResultsDropdown
                                }
                            }
                            .padding(.bottom, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Selected folder indicator chip - only in notes tab
                        if selectedTab == "notes", let folderId = selectedFolderId {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Text(notesManager.getFolderName(for: folderId))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Spacer()

                                Button(action: {
                                    withAnimation {
                                        selectedFolderId = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 4)
                        }
                    }
                    .background(
                        colorScheme == .dark ? Color.black : Color.white
                    )

                // Tab content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if selectedTab == "notes" {
                            notesTabContent
                        } else if selectedTab == "receipts" {
                            receiptsTabContent
                        } else {
                            recurringTabContent
                        }

                        // Bottom spacer for floating button
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }

                Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 0)
                .background(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .ignoresSafeArea()
                )
                .overlay(floatingAddButton)
                .overlay(folderSidebar)
            }
            .navigationDestination(for: Note.self) { note in
                NoteEditView(note: note, isPresented: .constant(true))
            }
            .overlay(alignment: .top) {
                // Receipt processing toast indicator (only show on receipts tab)
                if selectedTab == "receipts" && receiptProcessingState != .idle {
                    VStack {
                        ReceiptProcessingToast(state: receiptProcessingState)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(1000)
                }
            }
        }
        .fullScreenCover(isPresented: $showingNewNoteSheet) {
            NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
        }
        .sheet(isPresented: $showingRecurringExpenseForm) {
            RecurringExpenseForm { expense in
                HapticManager.shared.buttonTap()
                print("Created recurring expense: \(expense.title)")
            }
            .presentationBg()
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

    // MARK: - Tab Content Views

    private var notesTabContent: some View {
        Group {
                        // Pinned section card
                        if !filteredPinnedNotes.isEmpty {
                            VStack(spacing: 0) {
                                NoteSectionHeader(
                                    title: "PINNED",
                                    count: filteredPinnedNotes.count,
                                    isExpanded: $isPinnedExpanded
                                )

                                if isPinnedExpanded {
                                    ForEach(filteredPinnedNotes) { note in
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
                                            }
                                        )
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                    .shadow(
                                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )
                            )
                        }

                        // Recent section card (last 7 days)
                        if !recentNotes.isEmpty {
                            VStack(spacing: 0) {
                                NoteSectionHeader(
                                    title: "RECENT",
                                    count: recentNotes.count,
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
                                    ForEach(recentNotes) { note in
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
                                            }
                                        )
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                    .shadow(
                                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )
                            )
                        }

                        // Monthly sections for older notes
                        ForEach(notesByMonth.indices, id: \.self) { index in
                            let monthGroup = notesByMonth[index]

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
                                            }
                                        )
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                    .shadow(
                                        color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )
                            )
                        }

            // Empty state for notes tab
            if filteredPinnedNotes.isEmpty && recentNotes.isEmpty && notesByMonth.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                    Text(searchText.isEmpty ? "No notes yet" : "No notes found")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    if searchText.isEmpty {
                        Text("Tap the + button to create your first note")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 60)
            }
        }
    }
    
    // MARK: - Search Results Dropdown
    private var searchResultsDropdown: some View {
        let searchResults = notesManager.searchNotes(query: searchText).prefix(10)
        
        return VStack(spacing: 0) {
            if searchResults.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
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
                                .font(.system(size: 14))
                                .foregroundColor(note.isPinned ? .orange : .secondary)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                
                                Text(note.content.prefix(50).replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Date
                            Text(note.dateModified.formatted(.relative(presentation: .named)))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
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
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var receiptsTabContent: some View {
        ReceiptStatsView(searchText: searchText.isEmpty ? nil : searchText)
            .padding(.horizontal, -8) // Remove padding since content has its own
    }

    private var recurringTabContent: some View {
        RecurringExpenseStatsContent(searchText: searchText.isEmpty ? nil : searchText)
            .padding(.horizontal, -8) // Remove padding since content has its own
    }

    // MARK: - Helper Views

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // Show button on notes, receipts, and recurring tabs
                if selectedTab == "notes" || selectedTab == "receipts" || selectedTab == "recurring" {
                    if selectedTab == "receipts" {
                        // For receipts tab, show menu with gallery/camera options
                        Menu {
                            Button(action: {
                                HapticManager.shared.buttonTap()
                                showingReceiptCameraPicker = true
                            }) {
                                Label("Camera", systemImage: "camera.fill")
                            }
                            Button(action: {
                                HapticManager.shared.buttonTap()
                                showingReceiptImagePicker = true
                            }) {
                                Label("Gallery", systemImage: "photo.fill")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    } else {
                        // For notes and recurring tabs, show regular button
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            if selectedTab == "notes" {
                                showingNewNoteSheet = true
                            } else {
                                showingRecurringExpenseForm = true
                            }
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
    }

    private var folderSidebar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Dimmed background
                if showingFolderSidebar && selectedTab == "notes" {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showingFolderSidebar = false
                            }
                        }
                }

                // Sidebar - only show in notes tab
                if showingFolderSidebar && selectedTab == "notes" {
                    FolderSidebarView(
                        isPresented: $showingFolderSidebar,
                        selectedFolderId: $selectedFolderId
                    )
                    .frame(width: geo.size.width * 0.85)
                    .transition(.move(edge: .leading))
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if value.translation.width < -100 {
                                    withAnimation {
                                        showingFolderSidebar = false
                                    }
                                }
                            }
                    )
                }
            }
        }
        .allowsHitTesting(showingFolderSidebar && selectedTab == "notes")
    }

    // MARK: - Tab Color Helpers

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
        }
    }

    private func tabBackgroundColor() -> Color {
        return colorScheme == .dark ? .white : .black
    }

    private func tabContainerColor() -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
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
    @State private var undoHistory: [NSAttributedString] = []
    @State private var redoHistory: [NSAttributedString] = []
    @State private var noteIsLocked: Bool = false
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
    @StateObject private var openAIService = DeepSeekService.shared
    @State private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    @State private var showingImagePicker = false
    @State private var showingCameraPicker = false
    @State private var showingFileImporter = false
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var imageAttachments: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var showingAttachmentsSheet = false
    @State private var selectedImageIndex: Int = 0
    @State private var isKeyboardVisible = false
    @State private var isProcessingReceipt = false
    @State private var receiptProcessingState: ReceiptProcessingState = .idle
    @State private var isGeneratingTitle = false

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
    
    // Add More mode: "replace" or "append"
    @State private var addMoreMode: String = "append"

    var isAnyProcessing: Bool {
        isProcessingCleanup || isProcessingSummarize || isProcessingAddMore || isProcessingReceipt || isGeneratingTitle || isProcessingFile
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
        .alert("Add More Information", isPresented: $showingAddMorePrompt) {
            TextField("What would you like to add?", text: $addMorePromptText)
            Button("Cancel", role: .cancel) {
                addMorePromptText = ""
            }
            Button("Replace") {
                if !addMorePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await addMoreToNoteWithAI(userRequest: addMorePromptText, replaceExisting: true)
                    }
                }
            }
            Button("Append") {
                if !addMorePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await addMoreToNoteWithAI(userRequest: addMorePromptText, replaceExisting: false)
                    }
                }
            }
        } message: {
            Text("Replace removes existing text. Append adds after existing text.")
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

            VStack(spacing: 0) {
                // Custom toolbar - fixed at top
                customToolbar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? Color.black : Color.white)
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
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                } else {
                                    Text("Analyzing receipt...")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        }
                        
                        // Bottom padding to ensure content is scrollable above keyboard
                        Color.clear
                            .frame(height: 200)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 4)
                }
                .simultaneousGesture(
                    DragGesture()
                        .onEnded { gesture in
                            if gesture.translation.height > 50 {
                                // Swipe down detected - dismiss keyboard
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                )

                // Bottom buttons - fixed at bottom, outside scroll view
                VStack(spacing: 0) {
                    bottomActionButtons
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .zIndex(2)
            }
        }
    }


    // MARK: - View Components

    private var backgroundColor: some View {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var customToolbar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                HapticManager.shared.navigation()
                saveNoteAndDismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Undo button
            Button(action: {
                HapticManager.shared.buttonTap()
                undoLastChange()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }
            .disabled(undoHistory.isEmpty)
            .opacity(undoHistory.isEmpty ? 0.5 : 1.0)

            Spacer()

            // Share button
            Button(action: {
                HapticManager.shared.buttonTap()
                showingShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Folder button
            Button(action: {
                HapticManager.shared.folder()
                showingFolderPicker = true
            }) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Delete button
            Button(action: {
                HapticManager.shared.delete()
                deleteNote()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
            }
            .opacity(note != nil ? 1.0 : 0.5)
            .disabled(note == nil)

            // Lock/Unlock button
            Button(action: {
                HapticManager.shared.lockToggle()
                toggleLock()
            }) {
                Image(systemName: noteIsLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Save button
            Button(action: {
                HapticManager.shared.save()
                saveNoteAndDismiss()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
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
            // Title - smaller font (22pt), reduced padding (12pt)
            TextField("Title", text: $title, axis: .vertical)
                .font(.system(size: 22, weight: .bold))
                .submitLabel(.next)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            
            // Content editor with date detection
            UnifiedNoteEditor(
                text: $content,
                onEditingChanged: {
                    // No auto-save - save only on checkmark
                },
                onDateDetected: { date, context in
                    // User tapped highlighted date - parse event details with LLM
                    detectedEventDate = date
                    detectedEventEndDate = date.addingTimeInterval(3600)
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
            
            Spacer()
        }
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
                                    .font(.system(size: 14, weight: .medium))
                                Text("Remove")
                                    .font(.system(size: 14, weight: .medium))
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
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private var lockedStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                Text("Note is locked")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                VStack(spacing: 12) {
                    Button(action: {
                        authenticateWithBiometricOrPasscode()
                    }) {
                        Text("Unlock with Face ID or Passcode")
                            .font(.system(size: 16, weight: .medium))
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
                            .font(.system(size: 16, weight: .medium))
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

    private var bottomActionButtons: some View {
        // Bottom action buttons - 5 buttons in a row
        HStack(spacing: 8) {
            // AI button - Menu with 3 options
            Menu {
                Button(action: {
                    HapticManager.shared.aiActionStart()
                    Task {
                        await cleanUpNoteWithAI()
                    }
                }) {
                    Label("Clean up", systemImage: "sparkles")
                }
                .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                Button(action: {
                    HapticManager.shared.aiActionStart()
                    Task {
                        await summarizeNoteWithAI()
                    }
                }) {
                    Label("Summarize", systemImage: "text.bubble")
                }
                .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                Button(action: {
                    HapticManager.shared.aiActionStart()
                    showingAddMorePrompt = true
                }) {
                    Label("Add More", systemImage: "plus.circle")
                }
                .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } label: {
                if isProcessingCleanup || isProcessingSummarize || isProcessingAddMore {
                    ShadcnSpinner(size: .small)
                        .frame(height: 36)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 40, height: 36)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
            .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Spacer
            Spacer()
            
            // Todo checkbox button
            Button(action: {
                HapticManager.shared.buttonTap()
                insertTodoAtCursor()
            }) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )

            // File icon button
            Button(action: {
                showingFileImporter = true
            }) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )

            // Gallery icon button
            Button(action: {
                showingImagePicker = true
            }) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )

            // View attachments button - only shows if there are images or files
            if !imageAttachments.isEmpty || attachment != nil {
                Button(action: {
                    HapticManager.shared.buttonTap()
                    // Show image attachments sheet if available
                    if !imageAttachments.isEmpty {
                        showingAttachmentsSheet = true
                    } else if let attachment = attachment {
                        // Download and show file preview
                        Task {
                            do {
                                print("📥 Downloading file for preview: \(attachment.fileName)")
                                print("📥 Storage path: \(attachment.storagePath)")

                                // Download the file from storage using AttachmentService
                                let fileData = try await AttachmentService.shared.downloadFile(from: attachment.storagePath)

                                print("✅ Downloaded \(fileData.count) bytes")

                                // Save to temporary file for preview
                                let tmpDirectory = FileManager.default.temporaryDirectory
                                let tmpFile = tmpDirectory.appendingPathComponent(attachment.fileName)

                                try fileData.write(to: tmpFile)

                                print("✅ File saved to temp location: \(tmpFile.path)")

                                await MainActor.run {
                                    self.filePreviewURL = tmpFile
                                    self.showingFilePreview = true
                                }
                            } catch {
                                print("❌ Failed to download file for preview: \(error)")
                                print("📊 Storage path that failed: \(attachment.storagePath)")
                                print("📊 File name: \(attachment.fileName)")
                                await MainActor.run {
                                    HapticManager.shared.error()
                                }
                            }
                        }
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "eye")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 40, height: 36)

                        // Badge showing total attachment count
                        let totalCount = imageAttachments.count + (attachment != nil ? 1 : 0)
                        Text("\(totalCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)))
                            .offset(x: 8, y: -4)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color.black : Color.white)
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

        // If title is empty but content exists, generate title with AI
        if trimmedTitle.isEmpty && (!trimmedContent.isEmpty || !imageAttachments.isEmpty) {
            isGeneratingTitle = true
            Task {
                do {
                    let generatedTitle = try await openAIService.generateNoteTitle(from: trimmedContent.isEmpty ? "Image attachment" : trimmedContent)
                    await performSave(title: generatedTitle, content: contentToSave)
                    await MainActor.run {
                        self.title = generatedTitle
                        isGeneratingTitle = false
                        dismiss()
                    }
                } catch {
                    // If AI fails, use timestamp as fallback
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                    await performSave(title: timestamp, content: contentToSave)
                    await MainActor.run {
                        self.title = "Note \(timestamp)"
                        isGeneratingTitle = false
                        dismiss()
                    }
                }
            }
            return
        }

        // CRITICAL: Wait for save to complete before dismissing
        Task {
            await performSave(title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle, content: contentToSave)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func performSave(title: String, content: String) async {
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
        // Create combined attributed string with title
        let titleAttrString = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
            ]
        )
        let separator = NSAttributedString(string: "\n---\n")
        let combined = NSMutableAttributedString()
        combined.append(titleAttrString)
        combined.append(separator)
        combined.append(attributedContent)

        if let last = undoHistory.last, !last.isEqual(to: combined) {
            undoHistory.append(combined)
            if undoHistory.count > 20 { // Limit history
                undoHistory.removeFirst()
            }
            redoHistory.removeAll() // Clear redo when new changes are made
        } else if undoHistory.isEmpty {
            undoHistory.append(combined)
        }
    }

    private func undoLastChange() {
        guard undoHistory.count > 1 else { return }

        let currentState = undoHistory.removeLast()
        redoHistory.append(currentState)

        if let previousState = undoHistory.last {
            let text = previousState.string
            let components = text.components(separatedBy: "\n---\n")
            if components.count >= 2 {
                title = components[0]
                // Extract attributed content after separator
                if let range = previousState.string.range(of: "\n---\n") {
                    let contentStartIndex = previousState.string.distance(from: previousState.string.startIndex, to: range.upperBound)
                    let contentRange = NSRange(location: contentStartIndex, length: previousState.length - contentStartIndex)
                    attributedContent = previousState.attributedSubstring(from: contentRange)
                    content = attributedContent.string
                }
            }
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

    private func addMoreToNoteWithAI(userRequest: String, replaceExisting: Bool = false) async {
        guard !userRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingAddMore = true
        saveToUndoHistory()

        do {
            // Get expanded text from AI
            let aiResponse = try await openAIService.addMoreToNoteText(content, userRequest: userRequest)
            
            // Strip markdown syntax for clean output
            let cleanText = stripMarkdownSyntax(aiResponse)

            await MainActor.run {
                if replaceExisting {
                    // Replace: Clear existing and use new content
                    content = cleanText
                } else {
                    // Append: Add after existing content
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        content = cleanText
                    } else {
                        content = content + "\n\n" + cleanText
                    }
                }
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
    
    // Strip markdown syntax for clean display
    private func stripMarkdownSyntax(_ text: String) -> String {
        var result = text
        // Remove bold **text** -> text (non-greedy, handles multiline)
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [.dotMatchesLineSeparators]) {
            result = boldRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }
        // Remove italic *text* -> text (single asterisk, not double)
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", options: []) {
            result = italicRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }
        // Remove heading prefixes # ## ### at start of lines (multiline mode)
        if let headingRegex = try? NSRegularExpression(pattern: "^#{1,3}\\s+", options: [.anchorsMatchLines]) {
            result = headingRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
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
            Extract event details from this text. Return ONLY a valid JSON object.
            
            Text: "\(context)"
            Detected base date: \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
            
            Extract and return JSON with these fields:
            - title: A SHORT event name (max 5-6 words, like "Meeting with Bob" or "Doctor Appointment")
            - description: Any additional details, context, or notes (everything that's not the title)
            - startTime: Time in HH:mm 24-hour format if mentioned (e.g., "2pm" -> "14:00", "3:30pm" -> "15:30")
            - endTime: End time in HH:mm format if mentioned, otherwise null
            - location: Location or place if mentioned, otherwise null
            - reminder: One of ["none", "15min", "1hour", "3hours", "1day"] if user mentions reminder/alert, otherwise "15min" as default
            
            Example input: "Meeting with John at 2pm tomorrow at Starbucks to discuss project"
            Example output: {"title": "Meeting with John", "description": "Discuss project", "startTime": "14:00", "endTime": null, "location": "Starbucks", "reminder": "15min"}
            
            Example input: "Call mom at 5:30pm remind me 30 minutes before"
            Example output: {"title": "Call mom", "description": null, "startTime": "17:30", "endTime": null, "location": null, "reminder": "30min"}
            
            IMPORTANT: Title should be CONCISE (3-6 words max). Put all other info in description.
            Return ONLY the JSON, no other text.
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
                    // Title - keep it short
                    if let title = json["title"] as? String, !title.isEmpty {
                        detectedEventTitle = title
                    } else {
                        // Extract first few words as title
                        let words = context.split(separator: " ").prefix(5).joined(separator: " ")
                        detectedEventTitle = words
                    }
                    
                    // Description
                    if let desc = json["description"] as? String, !desc.isEmpty, desc != "null" {
                        detectedEventDescription = desc
                    }
                    
                    // Parse time if present
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
                    
                    // Location - add to description if present
                    if let location = json["location"] as? String, !location.isEmpty, location != "null" {
                        if detectedEventDescription.isEmpty {
                            detectedEventDescription = "📍 \(location)"
                        } else {
                            detectedEventDescription = "📍 \(location)\n\(detectedEventDescription)"
                        }
                    }
                    
                    // Reminder
                    if let reminderStr = json["reminder"] as? String {
                        switch reminderStr.lowercased() {
                        case "none": eventReminder = .none
                        case "5min", "15min": eventReminder = .fifteenMinutes
                        case "30min", "1hour": eventReminder = .oneHour
                        case "3hours": eventReminder = .threeHours
                        case "1day": eventReminder = .oneDay
                        default: eventReminder = .fifteenMinutes
                        }
                    }
                    
                    isParsingEventFromNote = false
                }
            } else {
                // Fallback: use smart extraction
                await MainActor.run {
                    let words = context.split(separator: " ")
                    detectedEventTitle = words.prefix(5).joined(separator: " ")
                    if words.count > 5 {
                        detectedEventDescription = words.dropFirst(5).joined(separator: " ")
                    }
                    isParsingEventFromNote = false
                }
            }
        } catch {
            // Fallback on error
            await MainActor.run {
                let words = context.split(separator: " ")
                detectedEventTitle = words.prefix(5).joined(separator: " ")
                if words.count > 5 {
                    detectedEventDescription = words.dropFirst(5).joined(separator: " ")
                }
                isParsingEventFromNote = false
            }
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
                let openAIService = DeepSeekService.shared
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
                            .font(.system(size: 20, weight: .semibold))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24)
                                Text("Insert Table")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }
                    } header: {
                        Text("Insert")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }

                    Section {
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            onApplyFormatting(.bold)
                        }) {
                            HStack {
                                Image(systemName: "bold")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Bold")
                                    .font(.system(size: 16, weight: .medium))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Italic")
                                    .font(.system(size: 16, weight: .medium))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Underline")
                                    .font(.system(size: 16, weight: .medium))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Heading 1")
                                    .font(.system(size: 16, weight: .medium))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                                    .frame(width: 24)
                                Text("Heading 2")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(hasSelection ? (colorScheme == .dark ? .white : .black) : .gray)
                            }
                        }
                        .disabled(!hasSelection)
                    } header: {
                        Text("Text Formatting")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    } footer: {
                        if !hasSelection {
                            Text("Select text to apply formatting")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .scrollContentBackground(.hidden)
                .background(colorScheme == .dark ? Color.black : Color.white)
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

#Preview {
    NotesView()
}