import SwiftUI

struct SearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var searchService = SearchService.shared
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedEmail: Email?
    @State private var selectedTask: TaskItem?
    @State private var selectedNote: Note?
    @State private var showingEditTask = false

    enum SearchResultType {
        case email, event, note
    }

    struct SearchResult: Identifiable {
        let id = UUID()
        let type: SearchResultType
        let title: String
        let subtitle: String
        let icon: String
        let data: Any
    }

    private var searchResults: [SearchResult] {
        guard !searchText.isEmpty else { return [] }

        var results: [SearchResult] = []
        let lowercasedSearch = searchText.lowercased()

        // Search emails
        let matchingEmails = emailService.inboxEmails.filter {
            $0.subject.lowercased().contains(lowercasedSearch) ||
            $0.sender.displayName.lowercased().contains(lowercasedSearch) ||
            $0.snippet.lowercased().contains(lowercasedSearch)
        }
        results += matchingEmails.map { email in
            SearchResult(
                type: .email,
                title: email.subject,
                subtitle: "from \(email.sender.displayName)",
                icon: "envelope.fill",
                data: email
            )
        }

        // Search tasks/events
        let allTasks = taskManager.getAllTasksIncludingArchived()
        let matchingTasks = allTasks.filter {
            $0.title.lowercased().contains(lowercasedSearch)
        }
        results += matchingTasks.map { task in
            SearchResult(
                type: .event,
                title: task.title,
                subtitle: task.scheduledTime != nil ? formatDateAndTime(task.scheduledTime!) : "No time set",
                icon: "calendar",
                data: task
            )
        }

        // Search notes
        let allNotes = notesManager.notes
        let matchingNotes = allNotes.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.content.lowercased().contains(lowercasedSearch)
        }
        results += matchingNotes.map { note in
            SearchResult(
                type: .note,
                title: note.title,
                subtitle: note.formattedDateModified,
                icon: "note.text",
                data: note
            )
        }

        return results
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Extracted Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    HapticManager.shared.selection()
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text("Search")
                    .font(FontManager.geist(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()

                // Invisible spacer for centering
                Image(systemName: "xmark")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            searchFieldView
        }
        .padding(.bottom, 16)
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }
    
    private var searchFieldView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            TextField("Search emails, events, notes...", text: $searchText)
                .focused($isSearchFocused)
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchText) { newValue in
                    searchService.searchQuery = newValue
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchService.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 48, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                .padding(.top, 60)

            Text("Search your emails, events, and notes")
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(FontManager.geist(size: 48, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .padding(.top, 60)

            Text("No results found")
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            Text("Ask AI about this instead")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

            chatWithAIButton

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chatWithAIButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            let messageToAdd = searchText
            Task {
                await searchService.addConversationMessage(messageToAdd)
            }
            isPresented = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(FontManager.geist(size: 14, weight: .medium))

                Text("Chat with AI")
                    .font(FontManager.geist(size: 15, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
            )
        }
        .padding(.horizontal, 40)
    }
    
    private var searchResultsListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(searchResults) { result in
                    searchResultRow(result)
                    
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }
    
    private func searchResultRow(_ result: SearchResult) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            handleResultTap(result)
        }) {
            HStack(spacing: 12) {
                Image(systemName: result.icon)
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleResultTap(_ result: SearchResult) {
        switch result.type {
        case .email:
            if let email = result.data as? Email {
                selectedEmail = email
            }
        case .event:
            if let task = result.data as? TaskItem {
                showingEditTask = false
                selectedTask = task
            }
        case .note:
            if let note = result.data as? Note {
                selectedNote = note
            }
        }
    }
    
    @ViewBuilder
    private var searchContentView: some View {
        if searchText.isEmpty {
            emptySearchView
        } else if searchResults.isEmpty {
            noResultsView
        } else {
            searchResultsListView
        }
    }
    
    @ViewBuilder
    private func taskSheetContent(task: TaskItem) -> some View {
        if showingEditTask {
            NavigationView {
                EditTaskView(
                    task: task,
                    onSave: { updatedTask in
                        taskManager.editTask(updatedTask)
                        selectedTask = nil
                        showingEditTask = false
                    },
                    onCancel: {
                        selectedTask = nil
                        showingEditTask = false
                    },
                    onDelete: { taskToDelete in
                        taskManager.deleteTask(taskToDelete)
                        selectedTask = nil
                        showingEditTask = false
                    },
                    onDeleteRecurringSeries: { taskToDelete in
                        taskManager.deleteRecurringTask(taskToDelete)
                        selectedTask = nil
                        showingEditTask = false
                    }
                )
            }
        } else {
            NavigationView {
                ViewEventView(
                    task: task,
                    onEdit: {
                        showingEditTask = true
                    },
                    onDelete: { taskToDelete in
                        taskManager.deleteTask(taskToDelete)
                        selectedTask = nil
                    },
                    onDeleteRecurringSeries: { taskToDelete in
                        taskManager.deleteRecurringTask(taskToDelete)
                        selectedTask = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            searchContentView
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .onAppear {
            isSearchFocused = true
        }
        .fullScreenCover(item: $selectedEmail) { email in
            NavigationView {
                EmailDetailView(email: email)
            }
            .presentationBg()
        }
        .sheet(item: $selectedTask) { task in
            taskSheetContent(task: task)
                .presentationBg()
        }
        .sheet(item: $selectedNote) { note in
            NoteEditView(
                note: note,
                isPresented: Binding(
                    get: { selectedNote != nil },
                    set: { if !$0 { selectedNote = nil } }
                ),
                initialFolderId: nil
            )
            .presentationBg()
        }
    }
}

#Preview {
    SearchView(isPresented: .constant(true))
}
