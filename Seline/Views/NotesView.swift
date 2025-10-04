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

    var filteredPinnedNotes: [Note] {
        var notes: [Note]
        if searchText.isEmpty {
            notes = notesManager.pinnedNotes
        } else {
            notes = notesManager.searchNotes(query: searchText).filter { $0.isPinned && !$0.isDraft }
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
            notes = notesManager.searchNotes(query: searchText).filter { !$0.isPinned && !$0.isDraft }
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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Search header
                VStack(spacing: 8) {
                    NotesSearchBar(
                        searchText: $searchText,
                        showingFolderSidebar: $showingFolderSidebar,
                        selectedFolderId: $selectedFolderId
                    )
                }
                .padding(.top, 4)
                .padding(.bottom, 8)

                // Notes list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Sections in vertical layout with separator lines - matching home page structure
                        VStack(spacing: 0) {
                            // Pinned section
                            if !filteredPinnedNotes.isEmpty {
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

                            // Recent section (last 7 days)
                            if !recentNotes.isEmpty {
                                if !filteredPinnedNotes.isEmpty {
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                                        .frame(height: 1)
                                        .padding(.vertical, 16)
                                        .padding(.horizontal, -20)
                                }

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

                            // Monthly sections for older notes
                            ForEach(notesByMonth.indices, id: \.self) { index in
                                let monthGroup = notesByMonth[index]

                                if !filteredPinnedNotes.isEmpty || !recentNotes.isEmpty || index > 0 {
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                                        .frame(height: 1)
                                        .padding(.vertical, 16)
                                        .padding(.horizontal, -20)
                                }

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
                        }
                        .padding(.horizontal, 8)

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
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            .overlay(
                // Floating add button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingNewNoteSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(
                                            colorScheme == .dark ?
                                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                Color(red: 0.20, green: 0.34, blue: 0.40)
                                        )
                                )
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 60)
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
    @State private var showingCustomPrompt = false
    @State private var customPrompt = ""
    @State private var isProcessingCleanup = false
    @State private var isProcessingCustom = false
    @State private var showingShareSheet = false
    @State private var draftNoteId: UUID? = nil // Track the draft note being edited
    @StateObject private var openAIService = OpenAIService.shared
    @State private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    @State private var showingImagePicker = false
    @State private var imageAttachments: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var selectedImageIndex: Int = 0
    @State private var isKeyboardVisible = false

    var isAnyProcessing: Bool {
        isProcessingCleanup || isProcessingCustom
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
                // Custom toolbar
                customToolbar

                // Note content
                if !isLockedInSession {
                    noteContentView
                } else {
                    lockedStateView
                }

                bottomActionButtons
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
        .alert("Custom Edit", isPresented: $showingCustomPrompt) {
            TextField("Enter editing instructions (max 2 sentences)", text: $customPrompt)
            Button("Cancel", role: .cancel) {
                customPrompt = ""
            }
            Button("Apply") {
                Task {
                    await applyCustomEdit()
                }
            }
        } message: {
            Text("Enter your instructions in 1-2 sentences. Output will be text and links only.")
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
                        imageAttachments.append(image)
                    }
                }
            ))
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            if selectedImageIndex < imageAttachments.count {
                ImageViewer(image: imageAttachments[selectedImageIndex], isPresented: $showingImageViewer)
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
                saveNote()
                isPresented = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
            }

            // Undo button
            Button(action: {
                undoLastChange()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
            }
            .disabled(undoHistory.isEmpty)
            .opacity(undoHistory.isEmpty ? 0.5 : 1.0)

            Spacer()

            // Share button
            Button(action: {
                showingShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
            }

            // Folder button
            Button(action: {
                showingFolderPicker = true
            }) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
            }

            // Delete button
            Button(action: {
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
                toggleLock()
            }) {
                Image(systemName: noteIsLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
            }

            // Save button
            Button(action: {
                saveNote()
                isPresented = false
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
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var noteContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            TextField("", text: $title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .placeholder(when: title.isEmpty) {
                    Text("Note title")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .onChange(of: title) { newValue in
                    // Don't trigger saves during view updates
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)

            // Content - made larger and easier to tap
            VStack(spacing: 0) {
                // Scrollable text editor
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
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
                        .frame(minHeight: geometry.size.height)
                    }
                }

                // Fixed Image Attachments Section at bottom (collapsible)
                if !imageAttachments.isEmpty {
                    imageAttachmentsView
                }
            }
        }
    }

    private var imageAttachmentsView: some View {
        VStack(alignment: .leading, spacing: isKeyboardVisible ? 4 : 12) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                .frame(height: 1)

            Text("Attachments (\(imageAttachments.count))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .padding(.horizontal, 32)

            if !isKeyboardVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(imageAttachments.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: imageAttachments[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        selectedImageIndex = index
                                        showingImageViewer = true
                                    }

                                // Delete button
                                Button(action: {
                                    imageAttachments.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.red))
                                        .font(.system(size: 20))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 8)
            }
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
        VStack(spacing: 0) {
            // Bottom action buttons
            HStack(spacing: 12) {
                // Clean up button - uses AI
                Button(action: {
                    Task {
                        await cleanUpNoteWithAI()
                    }
                }) {
                    if isProcessingCleanup {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                            .frame(width: 100)
                            .padding(.vertical, 12)
                    } else {
                        Text("Clean up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 100)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                )
                .disabled(isAnyProcessing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Custom button - allows user to enter their own prompt (up to 2 sentences)
                Button(action: {
                    showingCustomPrompt = true
                }) {
                    if isProcessingCustom {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                            .frame(width: 100)
                            .padding(.vertical, 12)
                    } else {
                        Text("Custom")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 100)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                )
                .disabled(isAnyProcessing)

                Spacer()

                // Image button
                Button(action: {
                    showingImagePicker = true
                }) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(Color.clear)
        }
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

            // Load image attachments
            imageAttachments = note.imageAttachments.compactMap { UIImage(data: $0) }

            noteIsLocked = note.isLocked
            selectedFolderId = note.folderId
            draftNoteId = note.id // Set the draft ID if editing existing note

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
        // Save note when leaving the view
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveNote()
        }
    }

    // MARK: - Actions

    private func saveNote() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        // Convert attributed content to plain text
        let contentToSave = convertAttributedContentToText()

        // Convert images to Data
        let imageData = imageAttachments.compactMap { $0.jpegData(compressionQuality: 0.8) }

        if let existingNote = note {
            var updatedNote = existingNote
            updatedNote.title = trimmedTitle
            updatedNote.content = contentToSave
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            updatedNote.imageAttachments = imageData
            notesManager.updateNote(updatedNote)
        } else {
            var newNote = Note(title: trimmedTitle, content: contentToSave, folderId: selectedFolderId)
            newNote.isLocked = noteIsLocked
            newNote.imageAttachments = imageData
            notesManager.addNote(newNote)
        }
    }

    private func convertAttributedContentToText() -> String {
        // For now, just return plain text without images
        // Images are stored as attachments locally only
        return content
    }

    private func saveDraft() {
        // Auto-save when user has typed something
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentToSave = convertAttributedContentToText()
        let trimmedContent = contentToSave.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only save if there's any content
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return }

        // Convert images to Data
        let imageData = imageAttachments.compactMap { $0.jpegData(compressionQuality: 0.8) }

        if let existingNote = note {
            // Updating an existing note
            var updatedNote = existingNote
            updatedNote.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
            updatedNote.content = contentToSave
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            updatedNote.imageAttachments = imageData
            notesManager.updateNote(updatedNote)
        } else if let draftId = draftNoteId {
            // Update existing auto-saved note that was created in this session
            if let existingDraft = notesManager.notes.first(where: { $0.id == draftId }) {
                var updatedNote = existingDraft
                updatedNote.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
                updatedNote.content = contentToSave
                updatedNote.isLocked = noteIsLocked
                updatedNote.folderId = selectedFolderId
                updatedNote.imageAttachments = imageData
                notesManager.updateNote(updatedNote)
            }
        } else {
            // Create new note only once
            var newNote = Note(
                title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
                content: contentToSave,
                folderId: selectedFolderId
            )
            newNote.isLocked = noteIsLocked
            newNote.imageAttachments = imageData
            draftNoteId = newNote.id // Store the ID to update later
            notesManager.addNote(newNote)
        }
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
        // Just return plain text content as attributed string
        // Images are stored locally only (not persisted to Supabase yet)
        return NSAttributedString(
            string: content,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
            ]
        )
    }

    // MARK: - AI-Powered Text Editing

    private func cleanUpNoteWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingCleanup = true
        saveToUndoHistory()

        do {
            let cleanedText = try await openAIService.cleanUpNoteText(content)
            await MainActor.run {
                content = cleanedText
                attributedContent = NSAttributedString(
                    string: cleanedText,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                    ]
                )
                isProcessingCleanup = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingCleanup = false
                print("Error cleaning up text: \(error.localizedDescription)")
            }
        }
    }

    private func applyCustomEdit() async {
        // Validate prompt
        let trimmedPrompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            customPrompt = ""
            return
        }

        // Count sentences (simple check for periods, exclamation marks, question marks)
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        let sentences = trimmedPrompt.components(separatedBy: sentenceEnders).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if sentences.count > 2 {
            // Show error - prompt too long
            await MainActor.run {
                customPrompt = ""
            }
            return
        }

        isProcessingCustom = true
        saveToUndoHistory()

        let prompt = trimmedPrompt + "\n\nIMPORTANT: Output should be text and links only. Do not include images, pictures, or media."
        customPrompt = ""

        do {
            let editedText = try await openAIService.customEditText(content.isEmpty ? "" : content, prompt: prompt)
            await MainActor.run {
                content = editedText
                attributedContent = NSAttributedString(
                    string: editedText,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
                    ]
                )
                isProcessingCustom = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingCustom = false
                print("Error with custom edit: \(error.localizedDescription)")
            }
        }
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

#Preview {
    NotesView()
}