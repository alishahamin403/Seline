import SwiftUI
import Contacts

struct ContactsImportView: View {
    @ObservedObject var peopleManager: PeopleManager
    let colorScheme: ColorScheme
    let onDismiss: () -> Void

    @State private var contacts: [CNContact] = []
    @State private var selectedIdentifiers: Set<String> = []
    @State private var alreadySyncedIdentifiers: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var importProgress: Int = 0
    @State private var importTotal: Int = 0
    @State private var permissionDenied = false
    @State private var importComplete = false
    @State private var showingLimitWarning = false
    @State private var showingClearHistoryConfirmation = false

    private let syncService = ContactsSyncService.shared
    private let MAX_IMPORT_LIMIT = 200

    private var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return contacts
        }
        let query = searchText.lowercased()
        return contacts.filter { contact in
            let fullName = "\(contact.givenName) \(contact.familyName)".lowercased()
            let org = contact.organizationName.lowercased()
            let phone = contact.phoneNumbers.first?.value.stringValue.lowercased() ?? ""
            return fullName.contains(query) || org.contains(query) || phone.contains(query)
        }
    }

    private var selectableContacts: [CNContact] {
        filteredContacts.filter { !alreadySyncedIdentifiers.contains($0.identifier) }
    }

    private var selectedCount: Int {
        selectedIdentifiers.count
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if permissionDenied {
                    permissionDeniedView
                } else if isLoading {
                    loadingView
                } else if contacts.isEmpty {
                    emptyStateView
                } else {
                    contactsListView
                }
            }
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            onDismiss()
                        }
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                        // Only show if there are synced contacts
                        if !alreadySyncedIdentifiers.isEmpty {
                            Button(action: {
                                showingClearHistoryConfirmation = true
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Import Contacts")
                        .font(FontManager.geist(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .task {
            await loadContacts()
        }
        .alert("Clear Import History?", isPresented: $showingClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                clearImportHistory()
            }
        } message: {
            Text("This will allow you to re-import previously imported contacts. It won't delete any existing people.")
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading contacts...")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

            Text("Contacts Access Required")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text("To import contacts, please allow Seline to access your contacts in Settings.")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Open Settings")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

            Text("No Contacts Found")
                .font(FontManager.geist(size: 18, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

            Text("Your iPhone contacts list appears to be empty.")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Contacts List View

    private var contactsListView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                    .font(.system(size: 14))

                TextField("Search contacts", text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Limit warning banner
            if showingLimitWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.primary)
                        .font(.system(size: 14))

                    Text("Maximum \(MAX_IMPORT_LIMIT) contacts can be imported at once. Additional contacts can be added manually.")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                        .lineLimit(2)

                    Spacer()

                    Button(action: { showingLimitWarning = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                            .font(.system(size: 16))
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.15))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Select All / Deselect All bar + count
            HStack(spacing: 12) {
                Text("\(selectedCount)/\(MAX_IMPORT_LIMIT) selected")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(selectedCount >= MAX_IMPORT_LIMIT
                        ? .primary
                        : (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)))

                Spacer()

                Button(action: selectAll) {
                    Text("Select All")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())

                Text("·")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                Button(action: deselectAll) {
                    Text("Deselect All")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Contact rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts, id: \.identifier) { contact in
                        contactRow(for: contact)

                        Divider()
                            .opacity(0.15)
                            .padding(.leading, 72)
                    }
                }
            }

            // Import button at the bottom
            importButton
        }
    }

    // MARK: - Contact Row

    private func contactRow(for contact: CNContact) -> some View {
        let isSynced = alreadySyncedIdentifiers.contains(contact.identifier)
        let isSelected = selectedIdentifiers.contains(contact.identifier)
        let fullName = contactDisplayName(contact)
        let phone = contact.phoneNumbers.first?.value.stringValue

        return Button(action: {
            guard !isSynced else { return }
            toggleSelection(contact.identifier)
        }) {
            HStack(spacing: 12) {
                // Avatar
                contactAvatar(for: contact)

                // Name and phone
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullName)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    if let phone = phone {
                        Text(phone)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Status indicator
                if isSynced {
                    Text("Already imported")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected
                            ? (colorScheme == .dark ? .white : .black)
                            : (colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.25)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isSynced ? 0.5 : 1.0)
    }

    // MARK: - Contact Avatar

    private func contactAvatar(for contact: CNContact) -> some View {
        Group {
            if let imageData = contact.thumbnailImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                let initials = contactInitials(contact)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.3, green: 0.7, blue: 0.5))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(initials)
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
    }

    // MARK: - Import Button

    private var importButton: some View {
        VStack(spacing: 8) {
            if isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: Double(importProgress), total: Double(max(importTotal, 1)))
                        .tint(colorScheme == .dark ? .white : .black)

                    Text("Importing \(importProgress)/\(importTotal)...")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                Button(action: {
                    Task { await importSelectedContacts() }
                }) {
                    Text(selectedCount > 0 ? "Import (\(selectedCount))" : "Import")
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(selectedCount > 0
                                    ? (colorScheme == .dark ? Color.white : Color.black)
                                    : (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedCount == 0)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .background(
            (colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
        )
    }

    // MARK: - Actions

    private func loadContacts() async {
        let status = syncService.authorizationStatus()
        if status == .denied || status == .restricted {
            await MainActor.run {
                permissionDenied = true
                isLoading = false
            }
            return
        }

        let fetched = await syncService.fetchAllContacts()
        let mapping = syncService.getContactMapping()
        let syncedIds = Set(mapping.keys)

        await MainActor.run {
            contacts = fetched
            alreadySyncedIdentifiers = syncedIds

            // Pre-select contacts up to limit
            let nonSyncedContacts = fetched.filter { !syncedIds.contains($0.identifier) }
            let contactsToSelect = Array(nonSyncedContacts.prefix(MAX_IMPORT_LIMIT))
            selectedIdentifiers = Set(contactsToSelect.map { $0.identifier })

            // Show warning if over limit
            if nonSyncedContacts.count > MAX_IMPORT_LIMIT {
                showingLimitWarning = true
            }

            isLoading = false

            // If permission was denied during fetch, show the denied view
            if fetched.isEmpty && syncService.authorizationStatus() != .authorized {
                permissionDenied = true
            }
        }
    }

    private func selectAll() {
        let available = selectableContacts.map { $0.identifier }
        let toSelect = Array(available.prefix(MAX_IMPORT_LIMIT))
        selectedIdentifiers = Set(toSelect)

        if available.count > MAX_IMPORT_LIMIT {
            showingLimitWarning = true
        }
    }

    private func deselectAll() {
        selectedIdentifiers.removeAll()
    }

    private func toggleSelection(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            // Check limit before adding
            if selectedIdentifiers.count >= MAX_IMPORT_LIMIT {
                showingLimitWarning = true
                return
            }
            selectedIdentifiers.insert(identifier)
        }
    }

    private func importSelectedContacts() async {
        let contactsToImport = contacts.filter { selectedIdentifiers.contains($0.identifier) }
        guard !contactsToImport.isEmpty else { return }

        await MainActor.run {
            isImporting = true
            importTotal = contactsToImport.count
            importProgress = 0
        }

        var newPeople: [Person] = []
        var mappingEntries: [(contactIdentifier: String, personId: UUID)] = []

        // Convert contacts to Person objects and upload photos (max 3 concurrent)
        for contact in contactsToImport {
            var person = syncService.convertContactToPerson(contact)

            // Upload photo if available
            if let imageData = contact.thumbnailImageData {
                let photoURL = await syncService.uploadContactPhoto(imageData, personId: person.id)
                person.photoURL = photoURL
            }

            newPeople.append(person)
            mappingEntries.append((contactIdentifier: contact.identifier, personId: person.id))

            await MainActor.run {
                importProgress += 1
            }
        }

        // Batch add all people
        await peopleManager.addPeople(newPeople)

        // Save dedup mapping
        syncService.saveContactMappingEntries(mappingEntries)

        await MainActor.run {
            isImporting = false
            importComplete = true

            // Update synced identifiers so they show as "Already imported"
            for entry in mappingEntries {
                alreadySyncedIdentifiers.insert(entry.contactIdentifier)
            }
            selectedIdentifiers.removeAll()
        }

        // Brief delay then dismiss
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            onDismiss()
        }
    }

    private func clearImportHistory() {
        syncService.clearSyncData()

        // Reload contacts to refresh the list
        Task {
            await loadContacts()
        }
    }

    // MARK: - Helpers

    private func contactDisplayName(_ contact: CNContact) -> String {
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? contact.organizationName : fullName
    }

    private func contactInitials(_ contact: CNContact) -> String {
        let first = contact.givenName.prefix(1)
        let last = contact.familyName.prefix(1)
        if !first.isEmpty && !last.isEmpty {
            return "\(first)\(last)".uppercased()
        }
        let name = contactDisplayName(contact)
        return String(name.prefix(2)).uppercased()
    }
}
