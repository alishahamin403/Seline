import SwiftUI

struct SearchOverlayBar: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: TabSelection
    @Binding var selectedNote: Note?
    @Binding var selectedEmail: Email?
    @Binding var selectedTask: TaskItem?
    @Binding var selectedLocation: SavedPlace?
    @Binding var selectedFolder: String?
    let onDismiss: () -> Void

    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var emailService = EmailService.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
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
                TextField("Search emails, events, notes, locations...", text: $searchText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .focused($isSearchFocused)

                // Microphone button
                Button(action: {
                    // TODO: Implement voice search
                    HapticManager.shared.selection()
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }

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
        case .location:
            // For locations, open directly in Google Maps
            if let location = result.location {
                GoogleMapsService.shared.openInGoogleMaps(place: location)
            }
            // Dismiss immediately for locations since we're opening an external app
            onDismiss()
            return
        case .folder:
            // For folders, navigate to Maps tab and set the selected folder
            if let category = result.category {
                selectedTab = .maps
                selectedFolder = category
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
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Search emails
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        let matchingEmails = allEmails.filter {
            $0.subject.lowercased().contains(lowercasedSearch) ||
            $0.sender.displayName.lowercased().contains(lowercasedSearch) ||
            $0.snippet.lowercased().contains(lowercasedSearch)
        }

        for email in matchingEmails.prefix(5) {
            results.append(OverlaySearchResult(
                type: .email,
                title: email.subject,
                subtitle: "from \(email.sender.displayName)",
                icon: "envelope",
                task: nil,
                email: email,
                note: nil,
                location: nil,
                category: nil
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
                note: note,
                location: nil,
                category: nil
            ))
        }

        // Search locations
        let matchingLocations = locationsManager.savedPlaces.filter {
            $0.name.lowercased().contains(lowercasedSearch) ||
            $0.address.lowercased().contains(lowercasedSearch) ||
            ($0.customName?.lowercased().contains(lowercasedSearch) ?? false)
        }

        for location in matchingLocations.prefix(5) {
            results.append(OverlaySearchResult(
                type: .location,
                title: location.displayName,
                subtitle: location.address,
                icon: "mappin.circle.fill",
                task: nil,
                email: nil,
                note: nil,
                location: location,
                category: nil
            ))
        }

        // Search folders/categories
        // When searching for a folder, also include locations within that folder
        let matchingCategories = locationsManager.categories.filter {
            $0.lowercased().contains(lowercasedSearch)
        }

        for category in matchingCategories.prefix(3) {
            let locationsInFolder = locationsManager.getPlaces(for: category)
            let subtitle = locationsInFolder.isEmpty ? "Empty folder" : "\(locationsInFolder.count) location\(locationsInFolder.count == 1 ? "" : "s")"

            results.append(OverlaySearchResult(
                type: .folder,
                title: category,
                subtitle: subtitle,
                icon: "folder.fill",
                task: nil,
                email: nil,
                note: nil,
                location: nil,
                category: category
            ))

            // Also add locations within the matching folder (limit to 3 per folder)
            for location in locationsInFolder.prefix(3) {
                results.append(OverlaySearchResult(
                    type: .location,
                    title: location.displayName,
                    subtitle: "\(category): \(location.address)",
                    icon: "mappin.circle.fill",
                    task: nil,
                    email: nil,
                    note: nil,
                    location: location,
                    category: category
                ))
            }
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
    let location: SavedPlace?
    let category: String?
}

enum OverlaySearchResultType: String {
    case email
    case event
    case note
    case location
    case folder
}
