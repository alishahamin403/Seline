import SwiftUI
import LocalAuthentication

/// New block-based note editor - Modern Notion-style editing
struct BlockNoteEditView: View {
    let note: Note?
    @Binding var isPresented: Bool
    let initialFolderId: UUID?

    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var attachmentService = AttachmentService.shared
    @StateObject private var blockController: BlockDocumentController
    @StateObject private var deepSeekService = DeepSeekService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var editingNote: Note?
    @State private var currentNoteId: UUID?
    @State private var selectedFolderId: UUID?
    @State private var showingFolderPicker = false
    @State private var showingShareSheet = false
    @State private var showingBlockTypePicker = false
    @State private var hasUnsavedChanges = false

    // Lock/authentication states
    @State private var isLockedInSession: Bool = false
    @State private var showingFaceIDPrompt: Bool = false
    @State private var noteIsLocked: Bool = false

    // Undo/redo
    @State private var undoHistory: [String] = []
    @State private var redoHistory: [String] = []

    // AI processing states
    @State private var isProcessingCleanup = false
    @State private var isProcessingSummarize = false
    @State private var isProcessingAddMore = false
    @State private var showingAddMorePrompt = false
    @State private var addMorePromptText = ""
    @State private var generatedContentForConfirmation: String? = nil
    @State private var showingAppendReplaceConfirmation = false
    @State private var showingEventCreationPrompt = false
    @State private var detectedEventDate: Date? = nil
    @State private var detectedEventTitle: String? = nil
    @State private var showAddEventPopup = false

    // Image attachments
    @State private var showingImagePicker = false
    @State private var showingCameraPicker = false
    @State private var showingReceiptImagePicker = false
    @State private var showingReceiptCameraPicker = false
    @State private var imageAttachments: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var showingAttachmentsSheet = false
    @State private var selectedImageIndex: Int = 0
    @State private var isProcessingReceipt = false

    // File attachments
    @State private var showingFileImporter = false
    @State private var attachment: NoteAttachment?
    @State private var extractedData: ExtractedData?
    @State private var showingExtractionSheet = false
    @State private var showingFilePreview = false
    @State private var filePreviewURL: URL?
    @State private var isProcessingFile = false

    var isAnyProcessing: Bool {
        isProcessingCleanup || isProcessingSummarize || isProcessingAddMore || isProcessingReceipt || isProcessingFile
    }

    init(note: Note?, isPresented: Binding<Bool>, initialFolderId: UUID? = nil) {
        self.note = note
        self._isPresented = isPresented
        self.initialFolderId = initialFolderId

        // Initialize block controller from note's blocks
        let initialBlocks = note?.blocks ?? [AnyBlock.text(TextBlock())]
        _blockController = StateObject(wrappedValue: BlockDocumentController(blocks: initialBlocks))
    }

    var body: some View {
        applyModifiers(to: ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom toolbar
                customToolbar
                    .zIndex(100)

                // Title field (or locked view)
                if !isLockedInSession {
                    VStack(spacing: 0) {
                        titleField

                        // Block editor
                        BlockListView(controller: blockController)
                            .background(backgroundColor)

                        Spacer()

                        // Processing indicator
                        if isProcessingReceipt || isProcessingFile {
                            HStack {
                                ShadcnSpinner(size: .small)
                                Text(isProcessingFile ? "Analyzing file..." : "Analyzing receipt...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }

                        // Bottom action buttons
                        bottomActionButtons
                            .zIndex(100)
                    }
                    .clipped()
                } else {
                    lockedStateView
                }
            }
        })
    }

    private func handleEventSave(title: String, description: String?, date: Date, time: Date?, endTime: Date?, reminder: ReminderTime?, recurring: Bool, frequency: RecurrenceFrequency?, customDays: [WeekDay]?, tagId: String?, location: String?) {
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: date)
        let weekday: WeekDay
        switch weekdayIndex {
        case 1: weekday = .sunday
        case 2: weekday = .monday
        case 3: weekday = .tuesday
        case 4: weekday = .wednesday
        case 5: weekday = .thursday
        case 6: weekday = .friday
        case 7: weekday = .saturday
        default: weekday = .monday
        }

        TaskManager.shared.addTask(
            title: title,
            to: weekday,
            description: description,
            scheduledTime: time,
            endTime: endTime,
            targetDate: date,
            reminderTime: reminder,
            location: location,
            isRecurring: recurring,
            recurrenceFrequency: frequency,
            tagId: tagId
        )
    }

    @ViewBuilder
    private func applyModifiers<V: View>(to content: V) -> some View {
        applyAlertModifiers(to: applySheetModifiers(to: applyLifecycleModifiers(to: content)))
    }
    
    @ViewBuilder
    private func applyLifecycleModifiers<V: View>(to content: V) -> some View {
        content
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .tabBar)
            .onAppear(perform: onAppear)
            .onChange(of: blockController.blocks) { blocks in
                hasUnsavedChanges = true
                scheduleAutoSave()
                checkForEvents(in: blocks)
            }
            .onChange(of: title) { _ in
                hasUnsavedChanges = true
                scheduleAutoSave()
            }
    }
    
    @ViewBuilder
    private func applySheetModifiers<V: View>(to content: V) -> some View {
        content
            .sheet(isPresented: $showingFolderPicker) {
                FolderPickerView(
                    selectedFolderId: $selectedFolderId,
                    isPresented: $showingFolderPicker
                )
                .presentationBg()
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: ["\(title)\n\n\(blockController.toMarkdown())"])
            }
            .sheet(isPresented: $showingBlockTypePicker) {
                BlockTypePickerView(
                    currentBlockId: blockController.focusedBlockId,
                    controller: blockController,
                    isPresented: $showingBlockTypePicker
                )
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
                allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText],
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
    }
    
    @ViewBuilder
    private func applyAlertModifiers<V: View>(to content: V) -> some View {
        content
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
                Text("Describe what additional information you'd like to add to your note.")
            }
            .confirmationDialog("Add AI Content", isPresented: $showingAppendReplaceConfirmation) {
                Button("Append to Note") {
                    if let content = generatedContentForConfirmation {
                        appendAIContent(content)
                    }
                }
                Button("Replace Note") {
                    if let content = generatedContentForConfirmation {
                        replaceNoteContent(content)
                    }
                }
                Button("Cancel", role: .cancel) {
                    generatedContentForConfirmation = nil
                }
            } message: {
                Text("How would you like to add the generated content?")
            }
            .alert("Create Event?", isPresented: $showingEventCreationPrompt) {
                Button("Create Event") {
                    showAddEventPopup = true
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                if let date = detectedEventDate {
                     Text("Found specific date: \(date.formatted(date: .abbreviated, time: .shortened)). Create an event?")
                } else {
                     Text("It looks like you're writing about an event. Would you like to add it to your calendar?")
                }
            }
            .sheet(isPresented: $showAddEventPopup) {
                if let date = detectedEventDate {
                    AddEventPopupView(
                        isPresented: $showAddEventPopup,
                        onSave: handleEventSave,
                        initialDate: date,
                        initialTime: date
                    )
                    .presentationBg()
                }
            }
            .alert("Authentication Failed", isPresented: $showingFaceIDPrompt) {
                Button("Cancel", role: .cancel) { }
                Button("Try Again") {
                    authenticateWithBiometricOrPasscode()
                }
            } message: {
                Text("Face ID or Touch ID authentication failed or is not available. Please try again.")
            }
    }

    private var backgroundColor: some View {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var customToolbar: some View {
        HStack(spacing: 12) {
            // Back button (saves automatically)
            Button(action: {
                saveAndDismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Unsaved changes indicator
            if hasUnsavedChanges {
                Text("Unsaved")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .orange.opacity(0.8) : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.1))
                    )
            }

            // Undo button
            Button(action: {
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
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }

            // Save button
            Button(action: {
                saveAndDismiss()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            colorScheme == .dark ? Color.white : Color.black
                        )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipped()
    }

    private var titleField: some View {
        TextField("Title", text: $title, axis: .vertical)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private func onAppear() {
        editingNote = note
        title = note?.title ?? ""
        selectedFolderId = note?.folderId ?? initialFolderId
        noteIsLocked = note?.isLocked ?? false
        currentNoteId = note?.id

        // Check if note is locked and requires authentication
        if let note = note, note.isLocked {
            isLockedInSession = true
            authenticateWithBiometricOrPasscode()
        }

        // Load image attachments
        if let note = note, !note.imageUrls.isEmpty {
            Task {
                var loadedImages: [UIImage] = []
                for imageUrl in note.imageUrls {
                    if let image = await ImageCacheManager.shared.getImage(url: imageUrl) {
                        loadedImages.append(image)
                    }
                }
                await MainActor.run {
                    imageAttachments = loadedImages
                }
            }
        }

        // Initialize undo history
        saveToUndoHistory()
    }

    private func scheduleAutoSave() {
        blockController.scheduleAutoSave {
            Task {
                await performAutoSave()
            }
        }
    }

    @MainActor
    private func performAutoSave() async {
        guard let existingNote = editingNote else { return }

        var updatedNote = existingNote
        updatedNote.title = title.isEmpty ? "Untitled" : title
        updatedNote.blocks = blockController.blocks
        updatedNote.folderId = selectedFolderId
        updatedNote.isLocked = noteIsLocked
        updatedNote.dateModified = Date()

        // OPTIMISTIC UPDATE: Update UI immediately (non-blocking)
        notesManager.updateNote(updatedNote)
        editingNote = updatedNote
        hasUnsavedChanges = false

        // Upload new images in background (non-blocking)
        if imageAttachments.count > existingNote.imageUrls.count {
            let newImages = Array(imageAttachments.suffix(imageAttachments.count - existingNote.imageUrls.count))
            Task {
                let newImageUrls = await notesManager.uploadNoteImages(newImages, noteId: existingNote.id)
                var finalNote = updatedNote
                finalNote.imageUrls = existingNote.imageUrls + newImageUrls
                finalNote.dateModified = Date()
                notesManager.updateNote(finalNote)  // Update with image URLs when ready
            }
        }

        // Sync with Supabase in background (non-blocking)
        // updateNote() already handles background syncing internally
        notesManager.updateNote(updatedNote)
    }

    private func saveAndDismiss() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Quick empty check first
        let hasTitle = !trimmedTitle.isEmpty
        let hasBlocks = !blockController.blocks.allSatisfy { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Don't save completely empty notes
        guard hasTitle || hasBlocks else {
            dismiss()
            return
        }

        // Capture data before dismissing
        let finalTitle = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        let finalBlocks = blockController.blocks
        let finalFolderId = selectedFolderId
        let finalIsLocked = noteIsLocked
        let finalImages = imageAttachments

        // Dismiss IMMEDIATELY - no blocking operations
        dismiss()

        // Do ALL save operations in background
        Task {
            if let existingNote = editingNote {
                // Update existing note
                var updatedNote = existingNote
                updatedNote.title = finalTitle
                updatedNote.blocks = finalBlocks
                updatedNote.folderId = finalFolderId
                updatedNote.isLocked = finalIsLocked
                updatedNote.dateModified = Date()

                // Handle new images
                if finalImages.count > existingNote.imageUrls.count {
                    let newImages = Array(finalImages.suffix(finalImages.count - existingNote.imageUrls.count))

                    notesManager.updateNote(updatedNote)

                    let newImageUrls = await notesManager.uploadNoteImages(newImages, noteId: existingNote.id)
                    var finalNote = updatedNote
                    finalNote.imageUrls = existingNote.imageUrls + newImageUrls
                    finalNote.dateModified = Date()
                    notesManager.updateNote(finalNote)
                } else {
                    notesManager.updateNote(updatedNote)
                }
            } else {
                // Create new note
                var newNote = Note(title: finalTitle, folderId: finalFolderId)
                newNote.blocks = finalBlocks
                newNote.isLocked = finalIsLocked

                notesManager.addNote(newNote)

                // Upload images if any
                if !finalImages.isEmpty {
                    let imageUrls = await notesManager.uploadNoteImages(finalImages, noteId: newNote.id)
                    var updatedNote = newNote
                    updatedNote.imageUrls = imageUrls
                    updatedNote.dateModified = Date()
                    notesManager.updateNote(updatedNote)
                }
            }
        }
    }

    private func appendAIContent(_ content: String) {
        let newBlocks = BlockDocumentController.parseMarkdown(content)
        blockController.blocks.append(contentsOf: newBlocks)
        generatedContentForConfirmation = nil
        saveToUndoHistory()
    }

    private func replaceNoteContent(_ content: String) {
        let newBlocks = BlockDocumentController.parseMarkdown(content)
        blockController.blocks = newBlocks
        generatedContentForConfirmation = nil
        saveToUndoHistory()
    }

    private func checkForEvents(in blocks: [AnyBlock]) {
        // Check the focused block first, otherwise fallback to last block
        let blockToCheck: AnyBlock?
        if let focusedId = blockController.focusedBlockId {
            blockToCheck = blocks.first(where: { $0.id == focusedId })
        } else {
            blockToCheck = blocks.last
        }

        guard let block = blockToCheck,
              let content = Optional(block.content),
              !content.isEmpty,
              content.count > 10 else { return }

        // Don't detect if we just showed it
        if showingEventCreationPrompt { return }

        Task {
            // Use NSDataDetector to find dates
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let matches = detector.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
                
                if let match = matches.first, let date = match.date {
                    // Only prompt for future dates or today
                    if date >= Calendar.current.startOfDay(for: Date()) {
                        await MainActor.run {
                            self.detectedEventDate = date
                            self.detectedEventTitle = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.showingEventCreationPrompt = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Action Buttons

    private var bottomActionButtons: some View {
        HStack(spacing: 8) {
            // AI button - Menu with 3 options
            Menu {
                Button(action: {
                    Task {
                        await cleanUpNoteWithAI()
                    }
                }) {
                    Label("Clean up", systemImage: "sparkles")
                }
                .disabled(isAnyProcessing || blockController.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: {
                    Task {
                        await summarizeNoteWithAI()
                    }
                }) {
                    Label("Summarize", systemImage: "text.bubble")
                }
                .disabled(isAnyProcessing || blockController.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: {
                    showingAddMorePrompt = true
                }) {
                    Label("Add More", systemImage: "plus.circle")
                }
                .disabled(isAnyProcessing || blockController.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .disabled(isAnyProcessing || blockController.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

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
                    if !imageAttachments.isEmpty {
                        showingAttachmentsSheet = true
                    } else if let attachment = attachment {
                        Task {
                            do {
                                let fileData = try await AttachmentService.shared.downloadFile(from: attachment.storagePath)
                                let tmpDirectory = FileManager.default.temporaryDirectory
                                let tmpFile = tmpDirectory.appendingPathComponent(attachment.fileName)
                                try fileData.write(to: tmpFile)

                                await MainActor.run {
                                    self.filePreviewURL = tmpFile
                                    self.showingFilePreview = true
                                }
                            } catch {
                                print("❌ Failed to download file: \(error)")
                            }
                        }
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "eye")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 40, height: 36)

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

    // MARK: - Supporting Views

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

    private var imageAttachmentsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(imageAttachments.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(uiImage: imageAttachments[index])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                selectedImageIndex = index
                                showingImageViewer = true
                            }

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
            }
            .padding(20)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    // MARK: - Helper Functions

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

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Unlock your note"

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isLockedInSession = false
                    } else {
                        if let authError = authenticationError {
                            print("Authentication error: \(authError.localizedDescription)")
                        }
                    }
                }
            }
        } else {
            print("Device authentication not available")
            showingFaceIDPrompt = true
        }
    }

    private func undoLastChange() {
        guard undoHistory.count > 1 else { return }

        let currentState = undoHistory.removeLast()
        redoHistory.append(currentState)

        if let previousMarkdown = undoHistory.last {
            let blocks = BlockDocumentController.parseMarkdown(previousMarkdown)
            blockController.blocks = blocks
        }
    }

    private func saveToUndoHistory() {
        let currentMarkdown = blockController.toMarkdown()
        if let last = undoHistory.last, last == currentMarkdown {
            return
        }
        undoHistory.append(currentMarkdown)
        if undoHistory.count > 20 {
            undoHistory.removeFirst()
        }
        redoHistory.removeAll()
    }

    // MARK: - AI Functions

    private func cleanUpNoteWithAI() async {
        let plainText = blockController.toPlainText()
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingCleanup = true
        saveToUndoHistory()

        do {
            let aiCleanedText = try await deepSeekService.cleanUpNoteText(plainText)
            let blocks = BlockDocumentController.parseMarkdown(aiCleanedText)

            await MainActor.run {
                blockController.blocks = blocks
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

    private func summarizeNoteWithAI() async {
        let plainText = blockController.toPlainText()
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingSummarize = true
        saveToUndoHistory()

        do {
            let summarizedText = try await deepSeekService.summarizeNoteText(plainText)
            let blocks = BlockDocumentController.parseMarkdown(summarizedText)

            await MainActor.run {
                blockController.blocks = blocks
                isProcessingSummarize = false
                saveToUndoHistory()
            }
        } catch {
            await MainActor.run {
                isProcessingSummarize = false
                print("Error summarizing text: \(error.localizedDescription)")
            }
        }
    }

    private func addMoreToNoteWithAI(userRequest: String) async {
        let plainText = blockController.toPlainText()
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !userRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isProcessingAddMore = true
        saveToUndoHistory()

        do {
            let expandedText = try await deepSeekService.addMoreToNoteText(plainText, userRequest: userRequest)
            
            await MainActor.run {
                generatedContentForConfirmation = expandedText
                isProcessingAddMore = false
                addMorePromptText = ""
                showingAppendReplaceConfirmation = true
            }
        } catch {
            await MainActor.run {
                isProcessingAddMore = false
                print("Error adding more to text: \(error.localizedDescription)")
            }
        }
    }

    private func processReceiptImage(_ image: UIImage) {
        Task {
            isProcessingReceipt = true

            do {
                let (receiptTitle, receiptContent) = try await deepSeekService.analyzeReceiptImage(image)

                await MainActor.run {
                    imageAttachments.append(image)

                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = receiptTitle
                    }

                    // Append receipt content as blocks
                    let receiptBlocks = BlockDocumentController.parseMarkdown(receiptContent)
                    blockController.blocks.append(contentsOf: receiptBlocks)

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

    private func handleFileSelected(_ url: URL) {
        // TODO: Implement file handling
        print("File selected: \(url)")
    }

    private func saveExtractedData(_ data: ExtractedData) async {
        // TODO: Implement extracted data saving
        print("Saving extracted data")
    }
}
