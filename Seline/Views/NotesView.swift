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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Search header
                VStack(spacing: 16) {
                    NotesSearchBar(
                        searchText: $searchText,
                        showingFolderSidebar: $showingFolderSidebar,
                        selectedFolderId: $selectedFolderId
                    )
                }
                .padding(.top, 8)
                .padding(.bottom, 12)

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
                        .padding(.horizontal, 20)

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
    @State private var isLockedInSession: Bool = false
    @State private var showingFaceIDPrompt: Bool = false
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []
    @State private var noteIsLocked: Bool = false
    @State private var selectedFolderId: UUID? = nil
    @State private var showingFolderPicker = false
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showingCustomPrompt = false
    @State private var customPrompt = ""
    @State private var isProcessingAI = false
    @StateObject private var openAIService = OpenAIService.shared

    init(note: Note?, isPresented: Binding<Bool>, initialFolderId: UUID? = nil) {
        self.note = note
        self._isPresented = isPresented
        self.initialFolderId = initialFolderId
    }

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom toolbar
                HStack(spacing: 16) {
                    // Back button
                    Button(action: {
                        saveNote()
                        isPresented = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                    }

                    // Undo button
                    Button(action: {
                        undoLastChange()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                    }
                    .disabled(undoHistory.isEmpty)
                    .opacity(undoHistory.isEmpty ? 0.5 : 1.0)

                    Spacer()

                    // Folder button
                    Button(action: {
                        showingFolderPicker = true
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                    }

                    // Delete button
                    Button(action: {
                        deleteNote()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.red))
                    }
                    .opacity(note != nil ? 1.0 : 0.5)
                    .disabled(note == nil)

                    // Lock/Unlock button
                    Button(action: {
                        toggleLock()
                    }) {
                        Image(systemName: noteIsLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                    }

                    // Save button
                    Button(action: {
                        saveNote()
                        isPresented = false
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
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
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Note content
                if !isLockedInSession {
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
                                saveToUndoHistory()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // Content - made larger and easier to tap
                        TextEditor(text: $content)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .background(Color.clear)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 20)
                            .onChange(of: content) { newValue in
                                saveToUndoHistory()
                            }
                    }
                } else {
                    // Locked state
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

                // Bottom action buttons
                HStack(spacing: 10) {
                    // Clean up button - uses AI
                    Button(action: {
                        Task {
                            await cleanUpNoteWithAI()
                        }
                    }) {
                        if isProcessingAI {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Clean up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                    )
                    .disabled(isProcessingAI || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    // Bullet Form button - uses AI
                    Button(action: {
                        Task {
                            await convertToBulletFormWithAI()
                        }
                    }) {
                        if isProcessingAI {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Bullet Form")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                    )
                    .disabled(isProcessingAI || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    // Custom button - allows user to enter their own prompt
                    Button(action: {
                        showingCustomPrompt = true
                    }) {
                        Text("Custom")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                    )
                    .disabled(isProcessingAI || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if let note = note {
                title = note.title
                content = note.content
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
            TextField("Enter editing instructions", text: $customPrompt)
            Button("Cancel", role: .cancel) {
                customPrompt = ""
            }
            Button("Apply") {
                Task {
                    await applyCustomEdit()
                }
            }
        } message: {
            Text("How would you like to edit this text? (e.g., \"make it more formal\", \"simplify\", \"add emojis\")")
        }
    }

    // MARK: - Actions

    private func saveNote() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let existingNote = note {
            var updatedNote = existingNote
            updatedNote.title = trimmedTitle
            updatedNote.content = content
            updatedNote.isLocked = noteIsLocked
            updatedNote.folderId = selectedFolderId
            notesManager.updateNote(updatedNote)
        } else {
            var newNote = Note(title: trimmedTitle, content: content, folderId: selectedFolderId)
            newNote.isLocked = noteIsLocked
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
        let currentState = title + "\n---\n" + content
        if undoHistory.last != currentState {
            undoHistory.append(currentState)
            if undoHistory.count > 20 { // Limit history
                undoHistory.removeFirst()
            }
            redoHistory.removeAll() // Clear redo when new changes are made
        }
    }

    private func undoLastChange() {
        guard undoHistory.count > 1 else { return }

        let currentState = undoHistory.removeLast()
        redoHistory.append(currentState)

        if let previousState = undoHistory.last {
            let components = previousState.components(separatedBy: "\n---\n")
            if components.count >= 2 {
                title = components[0]
                content = components[1]
            }
        }
    }

    // MARK: - AI-Powered Text Editing

    private func cleanUpNoteWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingAI = true
        saveToUndoHistory()

        do {
            let cleanedText = try await openAIService.cleanUpNoteText(content)
            await MainActor.run {
                content = cleanedText
                isProcessingAI = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingAI = false
                print("Error cleaning up text: \(error.localizedDescription)")
            }
        }
    }

    private func convertToBulletFormWithAI() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingAI = true
        saveToUndoHistory()

        do {
            let bulletText = try await openAIService.convertToBulletPoints(content)
            await MainActor.run {
                content = bulletText
                isProcessingAI = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingAI = false
                print("Error converting to bullets: \(error.localizedDescription)")
            }
        }
    }

    private func applyCustomEdit() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            customPrompt = ""
            return
        }

        isProcessingAI = true
        saveToUndoHistory()

        let prompt = customPrompt
        customPrompt = ""

        do {
            let editedText = try await openAIService.customEditText(content, prompt: prompt)
            await MainActor.run {
                content = editedText
                isProcessingAI = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingAI = false
                print("Error with custom edit: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NotesView()
}