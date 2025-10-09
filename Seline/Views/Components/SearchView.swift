import SwiftUI

struct SearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
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
        let allTasks = taskManager.tasks.values.flatMap { $0 }
        let matchingTasks = allTasks.filter {
            $0.title.lowercased().contains(lowercasedSearch)
        }
        results += matchingTasks.map { task in
            SearchResult(
                type: .event,
                title: task.title,
                subtitle: task.scheduledTime != nil ? formatTime(task.scheduledTime!) : "No time set",
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

    var body: some View {
        VStack(spacing: 0) {
            // Header with search bar
            VStack(spacing: 12) {
                HStack {
                    Button(action: {
                        HapticManager.shared.selection()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("Search")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                    Spacer()

                    // Invisible spacer for centering
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .opacity(0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    TextField("Search emails, events, notes...", text: $searchText)
                        .focused($isSearchFocused)
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
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
            .padding(.bottom, 16)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

            Divider()

            // Search results
            if searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .padding(.top, 60)

                    Text("Search your emails, events, and notes")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .padding(.top, 60)

                    Text("No results found")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                HapticManager.shared.selection()
                                // Handle result tap based on type
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
                            }) {
                                HStack(spacing: 12) {
                                    // Icon
                                    Image(systemName: result.icon)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(
                                            colorScheme == .dark ?
                                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                Color(red: 0.20, green: 0.34, blue: 0.40)
                                        )
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                            .lineLimit(1)

                                        Text(result.subtitle)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .onAppear {
            isSearchFocused = true
        }
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
        .sheet(item: $selectedTask) { task in
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
        .sheet(item: $selectedNote) { note in
            NoteEditView(
                note: note,
                isPresented: Binding(
                    get: { selectedNote != nil },
                    set: { if !$0 { selectedNote = nil } }
                ),
                initialFolderId: nil
            )
        }
    }
}

#Preview {
    SearchView(isPresented: .constant(true))
}
