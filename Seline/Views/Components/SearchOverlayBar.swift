import SwiftUI

struct SearchOverlayBar: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: TabSelection
    @Binding var selectedNote: Note?
    @Binding var selectedEmail: Email?
    @Binding var selectedTask: TaskItem?
    let onDismiss: () -> Void

    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var emailService = EmailService.shared
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                // Text field
                TextField("Search emails, events, notes...", text: $searchText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .focused($isSearchFocused)

                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }

                // Cancel button
                Button(action: {
                    searchText = ""
                    isSearchFocused = false
                    onDismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                colorScheme == .dark ?
                    Color(red: 0.15, green: 0.15, blue: 0.15) :
                    Color(red: 0.95, green: 0.95, blue: 0.95)
            )
            .cornerRadius(12)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

            // Search results
            if isPresented && !searchText.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                handleResultTap(result)
                            }) {
                                OverlaySearchResultRow(result: result, colorScheme: colorScheme)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if searchResults.isEmpty {
                            Text("No results found")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground :
                        Color.white
                )
                .cornerRadius(12)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .onAppear {
            if isPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
            }
        }
    }

    private func handleResultTap(_ result: OverlaySearchResult) {
        HapticManager.shared.selection()

        switch result.type {
        case .note:
            if let note = result.note {
                selectedNote = note
            }
        case .email:
            if let email = result.email {
                selectedEmail = email
            }
        case .event:
            if let task = result.task {
                selectedTask = task
            }
        }

        // Dismiss search overlay after setting the state
        onDismiss()
    }

    private var searchResults: [OverlaySearchResult] {
        guard !searchText.isEmpty else { return [] }
        var results: [OverlaySearchResult] = []
        let lowercasedSearch = searchText.lowercased()

        // Search tasks/events
        let allTasks = taskManager.tasks.values.flatMap { $0 }
        let matchingTasks = allTasks.filter {
            $0.title.lowercased().contains(lowercasedSearch)
        }

        for task in matchingTasks.prefix(5) {
            results.append(OverlaySearchResult(
                type: .event,
                title: task.title,
                subtitle: task.scheduledTime != nil ? formatTime(task.scheduledTime!) : "No time set",
                icon: "calendar",
                task: task,
                email: nil,
                note: nil
            ))
        }

        // Search emails
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        let matchingEmails = allEmails.filter {
            $0.subject.lowercased().contains(lowercasedSearch) ||
            $0.sender.displayName.lowercased().contains(lowercasedSearch) ||
            ($0.snippet ?? "").lowercased().contains(lowercasedSearch)
        }

        for email in matchingEmails.prefix(5) {
            results.append(OverlaySearchResult(
                type: .email,
                title: email.subject,
                subtitle: "from \(email.sender.displayName)",
                icon: "envelope",
                task: nil,
                email: email,
                note: nil
            ))
        }

        // Search notes
        let matchingNotes = notesManager.notes.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.content.lowercased().contains(lowercasedSearch)
        }

        for note in matchingNotes.prefix(5) {
            results.append(OverlaySearchResult(
                type: .note,
                title: note.title,
                subtitle: note.formattedDateModified,
                icon: "note.text",
                task: nil,
                email: nil,
                note: note
            ))
        }

        return results
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Search Result Row

struct OverlaySearchResultRow: View {
    let result: OverlaySearchResult
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Type badge
            Text(result.type.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.1) :
                        Color.black.opacity(0.05)
                )
                .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            colorScheme == .dark ?
                Color.white.opacity(0.05) :
                Color.black.opacity(0.03)
        )
        .cornerRadius(8)
    }
}

// MARK: - Search Result Model

struct OverlaySearchResult: Identifiable {
    let id = UUID()
    let type: OverlaySearchResultType
    let title: String
    let subtitle: String
    let icon: String
    let task: TaskItem?
    let email: Email?
    let note: Note?
}

enum OverlaySearchResultType: String {
    case email
    case event
    case note
}
