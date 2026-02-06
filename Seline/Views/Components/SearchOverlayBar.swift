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
            HStack(spacing: 8) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                // Text field
                TextField("Search emails, events, notes, locations...", text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .focused($isSearchFocused)

                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Cancel button
                Button(action: {
                    searchText = ""
                    isSearchFocused = false
                    onDismiss()
                }) {
                    Text("Cancel")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

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
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                .background(
                    colorScheme == .dark ?
                        Color(red: 0.11, green: 0.11, blue: 0.12) :
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
        case .receipt:
            // Receipts are linked to notes - open the note if available
            if let note = result.note {
                selectedNote = note
            }
        case .recurringExpense:
            // Recurring expenses are shown in Notes tab - navigate there
            selectedTab = .notes
        }

        // Dismiss search overlay after setting the state
        onDismiss()
    }

    private var searchResults: [OverlaySearchResult] {
        guard !searchText.isEmpty else { return [] }
        var results: [OverlaySearchResult] = []
        let lowercasedSearch = searchText.lowercased()

        // Search tasks/events
        let allTasks = taskManager.getAllTasksIncludingArchived()
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

        // Search notes - deduplicate to hide note versions when receipt versions exist
        let matchingNotes = notesManager.notes.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.content.lowercased().contains(lowercasedSearch)
        }

        // Separate notes with attachments (receipts) from those without
        let notesWithAttachments = matchingNotes.filter { $0.attachmentId != nil }
        let notesWithoutAttachments = matchingNotes.filter { $0.attachmentId == nil }

        // Filter out notes WITHOUT attachments if a similar note WITH attachment exists
        var filteredNotesWithoutAttachments: [Note] = []
        for noteWithout in notesWithoutAttachments {
            // Check if there's a matching note with attachment
            let hasMatchingReceipt = notesWithAttachments.contains { noteWith in
                // Compare titles by removing price and date patterns
                let title1 = noteWithout.title.lowercased()
                    .replacingOccurrences(of: #"\$[\d,]+\.?\d*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s*-\s*\w+\s+\d{1,2},?\s*\d{0,4}"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let title2 = noteWith.title.lowercased()
                    .replacingOccurrences(of: #"\$[\d,]+\.?\d*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s*-\s*\w+\s+\d{1,2},?\s*\d{0,4}"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Consider them duplicates if normalized titles match
                return title1 == title2 && !title1.isEmpty
            }

            // Only keep notes WITHOUT attachments if no matching receipt exists
            if !hasMatchingReceipt {
                filteredNotesWithoutAttachments.append(noteWithout)
            }
        }

        // Combine receipts and non-duplicate regular notes
        let finalNotes = (notesWithAttachments + filteredNotesWithoutAttachments)
            .sorted { $0.dateModified > $1.dateModified }

        for note in finalNotes.prefix(5) {
            if note.attachmentId != nil {
                // This is a receipt
                let amount = extractAmount(from: note.title)
                let subtitle: String
                if let amount = amount {
                    subtitle = String(format: "$%.2f • %@", amount, note.formattedDateModified)
                } else {
                    subtitle = note.formattedDateModified
                }

                results.append(OverlaySearchResult(
                    type: .receipt,
                    title: note.title,
                    subtitle: subtitle,
                    icon: "doc.text",
                    task: nil,
                    email: nil,
                    note: note,
                    location: nil,
                    category: nil
                ))
            } else {
                // This is a regular note
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

    private func extractAmount(from text: String) -> Double? {
        // Try to extract dollar amount from text like "$61.50" or "$59.00"
        let pattern = #"\$(\d+(?:,\d{3})*(?:\.\d{2})?)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let amountString = String(text[range]).replacingOccurrences(of: ",", with: "")
            return Double(amountString)
        }
        return nil
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
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Type badge
            Text(result.type.rawValue.capitalized)
                .font(FontManager.geist(size: 11, weight: .semibold))
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
    case receipt
    case recurringExpense
}
