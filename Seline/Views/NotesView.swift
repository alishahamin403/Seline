import SwiftUI
import LocalAuthentication

struct NotesView: View, Searchable {
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""
    @State private var showingNewNoteSheet = false
    @State private var selectedNote: Note? = nil
    @State private var isPinnedExpanded = true
    @State private var expandedSections: Set<String> = ["RECENT"]
    @State private var showingFolderSidebar = false
    @State private var selectedFolderId: UUID? = nil
    @State private var showReceiptStats = false

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

    // Notes updated in the last 7 days
    var recentNotes: [Note] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allUnpinnedNotes.filter { $0.dateModified >= oneWeekAgo }
    }

    // Group older notes by month
    var notesByMonth: [(month: String, notes: [Note])] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let olderNotes = allUnpinnedNotes.filter { $0.dateModified < oneWeekAgo }

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with search and stats toggle
                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        // Folders button
                        Button(action: {
                            withAnimation {
                                showingFolderSidebar.toggle()
                            }
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NotesSearchBar(
                            searchText: $searchText,
                            showingFolderSidebar: $showingFolderSidebar,
                            selectedFolderId: $selectedFolderId
                        )

                        // Stats button (only shown if there are receipts)
                        if hasReceipts {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showReceiptStats.toggle()
                                }
                            }) {
                                Image(systemName: "dollarsign")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            // Spacer to keep layout consistent when no receipts
                            Color.clear
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 2)
                .padding(.bottom, 4)

                // Conditional rendering: Stats view or Notes list
                if showReceiptStats {
                    ReceiptStatsView()
                } else {
                    // Notes list
                    ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
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
                                                selectedNote = note
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
                                                selectedNote = note
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
                                                selectedNote = note
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

                        // Empty state
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

                        // Bottom spacer for floating button
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
            )
            .overlay(
                // Floating add button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.shared.buttonTap()
                            showingNewNoteSheet = true
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
            )
            .overlay(
                // Folder sidebar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Dimmed background
                        if showingFolderSidebar {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation {
                                        showingFolderSidebar = false
                                    }
                                }
                        }

                        // Sidebar
                        if showingFolderSidebar {
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
            )
        }
        .sheet(isPresented: $showingNewNoteSheet) {
            NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditView(note: note, isPresented: Binding<Bool>(
                get: { selectedNote != nil },
                set: { if !$0 { selectedNote = nil } }
            ))
        }
        .onAppear {
            // Register with search service
            SearchService.shared.registerSearchableProvider(self, for: .notes)
        }
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
            metadata: ["category": "productivity"]
        ))

        // Add notes content
        for note in notesManager.notes {
            items.append(SearchableItem(
                title: note.title,
                content: note.content,
                type: .notes,
                identifier: "note-\(note.id)",
                metadata: [
                    "isPinned": note.isPinned ? "true" : "false",
                    "dateModified": note.formattedDateModified,
                    "folder": notesManager.getFolderName(for: note.folderId)
                ]
            ))
        }

        return items
    }
}

// MARK: - Note Edit View

struct NoteEditView: View {
    let note: Note?
    @Binding var isPresented: Bool
    let initialFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var attributedContent: NSAttributedString = NSAttributedString()
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
    @State private var showingShareSheet = false
    @StateObject private var openAIService = OpenAIService.shared
    @State private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    @State private var showingImagePicker = false
    @State private var showingCameraPicker = false
    @State private var showingImageOptions = false
    @State private var showingReceiptOptions = false
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var imageAttachments: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var showingAttachmentsSheet = false
    @State private var selectedImageIndex: Int = 0
    @State private var isKeyboardVisible = false
    @State private var isProcessingReceipt = false
    @State private var isGeneratingTitle = false

    var isAnyProcessing: Bool {
        isProcessingCleanup || isProcessingReceipt || isGeneratingTitle
    }

    init(note: Note?, isPresented: Binding<Bool>, initialFolderId: UUID? = nil) {
        self.note = note
        self._isPresented = isPresented
        self.initialFolderId = initialFolderId
    }

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom toolbar - fixed at top
                customToolbar
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .zIndex(2)

                // Scrollable content area
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Note content
                        if !isLockedInSession {
                            noteContentView
                        } else {
                            lockedStateView
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { gesture in
                            // Dismiss keyboard when scrolling
                            if abs(gesture.translation.height) > 20 {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                        .onEnded { gesture in
                            // Swipe down to save and dismiss
                            if gesture.translation.height > 100 {
                                HapticManager.shared.save()
                                saveNoteAndDismiss()
                            }
                        }
                )

                // Receipt processing indicator - fixed above bottom buttons
                if isProcessingReceipt {
                    HStack {
                        ShadcnSpinner(size: .small)
                        Text("Analyzing receipt...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    }
                    .padding(.bottom, 4)
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .zIndex(1)
                }

                // Bottom buttons - fixed at bottom
                bottomActionButtons
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .zIndex(2)
            }
        }
        .navigationBarHidden(true)
        .onAppear(perform: onAppearAction)
        .onDisappear(perform: onDisappearAction)
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(
                selectedFolderId: $selectedFolderId,
                isPresented: $showingFolderPicker
            )
        }
        .alert("Authentication Failed", isPresented: $showingFaceIDPrompt) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                authenticateWithFaceID()
            }
        } message: {
            Text("Face ID or Touch ID authentication failed or is not available. Please try again.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let noteToShare = note {
                ShareSheet(activityItems: ["\(noteToShare.title)\n\n\(noteToShare.content)"])
            } else {
                ShareSheet(activityItems: ["\(title)\n\n\(content)"])
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        // Just attach image without AI processing
                        imageAttachments.append(image)
                    }
                }
            ))
        }
        .sheet(isPresented: $showingCameraPicker) {
            CameraPicker(selectedImage: Binding(
                get: { nil },
                set: { newImage in
                    if let image = newImage {
                        // Just attach image without AI processing
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
                        // Process receipt with AI
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
                        // Process receipt with AI
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
        }
        .confirmationDialog("Add Image", isPresented: $showingImageOptions, titleVisibility: .visible) {
            Button("Camera") {
                showingCameraPicker = true
            }
            Button("Gallery") {
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Add Receipt", isPresented: $showingReceiptOptions, titleVisibility: .visible) {
            Button("Camera") {
                showingReceiptCameraPicker = true
            }
            Button("Gallery") {
                showingReceiptImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
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
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            colorScheme == .dark ?
                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                Color(red: 0.20, green: 0.34, blue: 0.40)
                        )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var noteContentView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            TextField("", text: $title, axis: .vertical)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(nil)
                .placeholder(when: title.isEmpty) {
                    Text("Note title")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .onChange(of: title) { newValue in
                    // Don't trigger saves during view updates
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // Content - single text editor (table markers are hidden in the editor)
            FormattableTextEditor(
                attributedText: $attributedContent,
                colorScheme: colorScheme,
                onSelectionChange: { range in
                    selectedTextRange = range
                },
                onTextChange: { newAttributedText in
                    attributedContent = newAttributedText
                    content = newAttributedText.string
                }
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 0)
            .padding(.top, 8)

            // Tappable area to continue writing
            Color.clear
                .frame(minHeight: 300)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Ensure there's content after the last marker for cursor placement
                    if !content.hasSuffix("\n\n") {
                        let mutableAttrString = NSMutableAttributedString(attributedString: attributedContent)
                        let newlineString = NSAttributedString(
                            string: "\n\n",
                            attributes: [
                                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                                .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                            ]
                        )
                        mutableAttrString.append(newlineString)
                        attributedContent = mutableAttrString
                        content = attributedContent.string
                    }
                    // Dismiss keyboard is now handled by scroll gesture
                }
        }
    }

    private var imageAttachmentsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
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
                            if imageAttachments.isEmpty {
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
            }
            .padding(20)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private var lockedStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                Text("Note is locked")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                Button(action: {
                    authenticateWithFaceID()
                }) {
                    Text("Unlock with Face ID")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                        )
                }
            }
            Spacer()
        }
    }

    private var bottomActionButtons: some View {
        // Bottom action buttons - 5 buttons in a row
        HStack(spacing: 8) {
            // Clean up button - uses AI
            Button(action: {
                HapticManager.shared.aiActionStart()
                Task {
                    await cleanUpNoteWithAI()
                }
            }) {
                if isProcessingCleanup {
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

            // Todo list button - creates interactive todo list
            Spacer()

            // Attachments button - shows count if any
            Button(action: {
                HapticManager.shared.buttonTap()
                if !imageAttachments.isEmpty {
                    showingAttachmentsSheet = true
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 40, height: 36)

                    // Badge showing attachment count
                    if !imageAttachments.isEmpty {
                        Text("\(imageAttachments.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)))
                            .offset(x: 8, y: -4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
            .opacity(imageAttachments.isEmpty ? 0.5 : 1.0)

            // Gallery button - quick image attach without AI
            Button(action: {
                HapticManager.shared.imageAttachment()
                showingImageOptions = true
            }) {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )

            // Receipt button with AI processing options
            Button(action: {
                HapticManager.shared.imageAttachment()
                showingReceiptOptions = true
            }) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 36)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    // MARK: - Lifecycle Methods

    private func onAppearAction() {
        // Add keyboard observers
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            isKeyboardVisible = true
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            isKeyboardVisible = false
        }

        if let note = note {
            title = note.title
            content = note.content

            // Parse content and load images
            attributedContent = parseContentWithImages(note.content)

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

            noteIsLocked = note.isLocked
            selectedFolderId = note.folderId

            // If note is locked, require Face ID to unlock
            if note.isLocked {
                isLockedInSession = true
                authenticateWithFaceID()
            }
        } else if let folderId = initialFolderId {
            // Set initial folder for new note
            selectedFolderId = folderId
        }
        // Initialize undo history
        saveToUndoHistory()
    }

    private func onDisappearAction() {
        // Notes are only saved explicitly via save button or swipe down
        // No auto-save on disappear
    }

    // MARK: - Actions

    private func saveNoteAndDismiss() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentToSave = convertAttributedContentToText()
        let trimmedContent = contentToSave.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save completely empty notes
        guard !trimmedContent.isEmpty || !trimmedTitle.isEmpty || !imageAttachments.isEmpty else {
            isPresented = false
            return
        }

        // If title is empty but content exists, generate title with AI
        if trimmedTitle.isEmpty && (!trimmedContent.isEmpty || !imageAttachments.isEmpty) {
            isGeneratingTitle = true
            Task {
                do {
                    let generatedTitle = try await openAIService.generateNoteTitle(from: trimmedContent.isEmpty ? "Image attachment" : trimmedContent)
                    await MainActor.run {
                        self.title = generatedTitle
                        performSave(title: generatedTitle, content: contentToSave)
                        isGeneratingTitle = false
                        isPresented = false
                    }
                } catch {
                    // If AI fails, use timestamp as fallback
                    await MainActor.run {
                        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                        self.title = "Note \(timestamp)"
                        performSave(title: self.title, content: contentToSave)
                        isGeneratingTitle = false
                        isPresented = false
                    }
                }
            }
            return
        }

        performSave(title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle, content: contentToSave)
        isPresented = false
    }

    private func performSave(title: String, content: String) {
        if let existingNote = note {
            // Updating an existing note
            Task {
                var updatedNote = existingNote
                updatedNote.title = title
                updatedNote.content = content
                updatedNote.isLocked = noteIsLocked
                updatedNote.folderId = selectedFolderId

                // Check if there are new images to upload (compare count)
                if imageAttachments.count > existingNote.imageUrls.count {
                    // Upload only new images
                    let newImages = Array(imageAttachments.suffix(imageAttachments.count - existingNote.imageUrls.count))
                    let newImageUrls = await notesManager.uploadNoteImages(newImages, noteId: existingNote.id)
                    updatedNote.imageUrls = existingNote.imageUrls + newImageUrls
                }

                await MainActor.run {
                    notesManager.updateNote(updatedNote)
                }
            }
        } else {
            // Create new note
            Task {
                var newNote = Note(title: title, content: content, folderId: selectedFolderId)
                newNote.isLocked = noteIsLocked

                // Upload all images for new note
                if !imageAttachments.isEmpty {
                    let imageUrls = await notesManager.uploadNoteImages(imageAttachments, noteId: newNote.id)
                    newNote.imageUrls = imageUrls
                }

                await MainActor.run {
                    notesManager.addNote(newNote)
                }
            }
        }
    }

    // Save note immediately when tables are updated (without dismissing)
    private func saveNoteImmediately() {
        guard let existingNote = note else { return }

        Task {
            var updatedNote = existingNote
            updatedNote.title = title.isEmpty ? "Untitled" : title
            updatedNote.content = convertAttributedContentToText()
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            updatedNote.imageUrls = existingNote.imageUrls // Keep existing image URLs

            await MainActor.run {
                notesManager.updateNote(updatedNote)
            }
        }
    }

    private func convertAttributedContentToText() -> String {
        // Convert NSAttributedString to Markdown to preserve formatting (bold, italic, headings)
        // Table and todo markers are also preserved in the conversion
        // The markers will be hidden in the UI by the RichTextEditor's hideMarkers() function
        let markdown = AttributedStringToMarkdown.shared.convertToMarkdown(attributedContent)
        return markdown
    }


    private func deleteNote() {
        guard let note = note else { return }
        notesManager.deleteNote(note)
        isPresented = false
    }

    private func toggleLock() {
        noteIsLocked.toggle()
    }

    private func authenticateWithFaceID() {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Unlock your note with Face ID or Touch ID"

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isLockedInSession = false
                    } else {
                        // Authentication failed, show alert or dismiss
                        showingFaceIDPrompt = true
                        isPresented = false
                    }
                }
            }
        } else {
            // Biometric authentication not available, show alert
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
                        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                    ]
                )
            }
        }

        // New format: Markdown with table/todo markers (markers are hidden by RichTextEditor)
        // Parse the markdown to restore formatting like bold, italic, headings, etc.
        let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
        return MarkdownParser.shared.parseMarkdown(content, fontSize: 15, textColor: textColor)
    }

    // MARK: - AI-Powered Text Editing

    private func cleanUpNoteWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingCleanup = true
        saveToUndoHistory()

        do {
            let cleanedText = try await openAIService.cleanUpNoteText(content)
            await MainActor.run {
                // Parse and extract tables and todos from markdown
                let processedText = parseAndExtractTablesAndTodos(from: cleanedText)

                content = processedText
                // Use MarkdownParser to properly render formatting
                let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
                attributedContent = MarkdownParser.shared.parseMarkdown(
                    processedText,
                    fontSize: 15,
                    textColor: textColor
                )
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

    private func processReceiptImage(_ image: UIImage) {
        // Add image to attachments
        imageAttachments.append(image)

        // Process with AI
        Task {
            isProcessingReceipt = true

            do {
                let (receiptTitle, receiptContent) = try await openAIService.analyzeReceiptImage(image)

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

                await MainActor.run {
                    // Set title if empty or update it
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = receiptTitle
                    }

                    // Assign folder to receipt
                    if let folderId = folderIdForReceipt {
                        selectedFolderId = folderId
                    }

                    // Append receipt content to existing content
                    let newContent = content.isEmpty ? receiptContent : content + "\n\n" + receiptContent
                    content = newContent

                    // Convert markdown to attributed string
                    attributedContent = convertMarkdownToAttributedString(newContent)

                    isProcessingReceipt = false
                    saveToUndoHistory()
                }
            } catch {
                await MainActor.run {
                    isProcessingReceipt = false
                    print("Error analyzing receipt: \(error.localizedDescription)")
                }
            }
        }
    }

    private func convertMarkdownToAttributedString(_ text: String) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString()

        // Default attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
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
                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
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