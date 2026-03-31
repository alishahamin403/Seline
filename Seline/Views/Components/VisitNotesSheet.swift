import SwiftUI

struct VisitNotesSheet: View {
    enum ContentMode {
        case full
        case noteOnly
        case receiptOnly
    }

    let visit: LocationVisitRecord
    let place: SavedPlace?
    let colorScheme: ColorScheme
    let contentMode: ContentMode
    let onSave: (String) async -> Void
    let onDismiss: () -> Void

    @StateObject private var peopleManager = PeopleManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var receiptManager = ReceiptManager.shared

    @State private var notesText: String
    @State private var selectedPeopleIds: Set<UUID> = []
    @State private var selectedReceiptNoteId: UUID? = nil
    @State private var receiptSearchText: String = ""
    @State private var isLoadingPeople: Bool = true
    @State private var isLoadingReceipts: Bool = false
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    init(
        visit: LocationVisitRecord,
        place: SavedPlace?,
        colorScheme: ColorScheme,
        contentMode: ContentMode = .full,
        onSave: @escaping (String) async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.visit = visit
        self.place = place
        self.colorScheme = colorScheme
        self.contentMode = contentMode
        self.onSave = onSave
        self.onDismiss = onDismiss
        _notesText = State(initialValue: visit.visitNotes ?? "")
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    visitHeaderCard
                    if showsReasonSection {
                        reasonSection
                    }
                    if showsPeopleSection {
                        peopleSection
                    }
                    if showsReceiptSection {
                        receiptSection
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        persistChanges()
                    }
                    .disabled(isSaving)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .task {
                let existingPeople = showsPeopleSection
                    ? await peopleManager.getPeopleForVisit(visitId: visit.id)
                    : []
                await ensureReceiptDataLoaded()
                let existingReceiptNoteId = showsReceiptSection
                    ? VisitReceiptLinkStore.receiptId(for: visit.id)
                    : nil
                await MainActor.run {
                    selectedPeopleIds = Set(existingPeople.map { $0.id })
                    selectedReceiptNoteId = existingReceiptNoteId
                    isLoadingPeople = false
                }
            }
            .onAppear {
                if showsReasonSection {
                    isFocused = true
                }
            }
        }
    }

    private var showsReasonSection: Bool {
        contentMode != .receiptOnly
    }

    private var showsPeopleSection: Bool {
        contentMode == .full
    }

    private var showsReceiptSection: Bool {
        contentMode != .noteOnly
    }

    private var navigationTitle: String {
        switch contentMode {
        case .full:
            return "Visit Details"
        case .noteOnly:
            return "Visit Note"
        case .receiptOnly:
            return "Attach Receipt"
        }
    }

    private var visitHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                Text(place?.displayName ?? "Visit")
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(timeRangeString)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.65))

                if let duration = visit.durationMinutes {
                    Text("• \(durationString(minutes: duration))")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.65))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "square.and.pencil", title: "Visit reason")

            TextField(
                "Why did you visit? Add context you want to remember...",
                text: $notesText,
                axis: .vertical
            )
            .font(FontManager.geist(size: 15, weight: .regular))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .lineLimit(4...10)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
            .focused($isFocused)
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "person.2.fill", title: "People connected")

            if isLoadingPeople {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Loading people...")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .padding(.vertical, 8)
            } else {
                PeoplePickerView(
                    peopleManager: peopleManager,
                    selectedPeopleIds: $selectedPeopleIds,
                    colorScheme: colorScheme,
                    title: "Search and select",
                    showHeader: false,
                    maxHeight: 220
                )
            }
        }
    }

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "receipt.fill", title: "Attach receipt")

            if let selected = selectedReceipt {
                selectedReceiptPill(for: selected)
            }

            receiptSearchField

            if isLoadingReceipts {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Loading receipts...")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .padding(.vertical, 8)
            } else if filteredReceipts.isEmpty {
                Text(receiptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No receipts available" : "No matching receipts")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.55))
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(filteredReceipts, id: \.id) { receipt in
                            receiptRow(receipt: receipt)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var receiptSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

            TextField("Search receipts...", text: $receiptSearchText)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            if !receiptSearchText.isEmpty {
                Button(action: { receiptSearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        )
    }

    private func receiptRow(receipt: ReceiptStat) -> some View {
        let isSelected = selectedReceiptNoteId == receipt.id

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedReceiptNoteId = nil
                } else {
                    selectedReceiptNoteId = receipt.id
                }
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "receipt")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.title)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Text("\(CurrencyParser.formatAmount(receipt.amount)) • \(shortDateString(from: receipt.date))")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(FontManager.geist(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.2))
                        : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func selectedReceiptPill(for receipt: ReceiptStat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.75) : .black.opacity(0.75))

            Text(receipt.title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: {
                selectedReceiptNoteId = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.55))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.06))
        )
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))

            Text(title)
                .font(FontManager.geist(size: 15, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    private var selectedReceipt: ReceiptStat? {
        guard let receiptId = selectedReceiptNoteId else { return nil }
        return receiptManager.receipt(by: receiptId)
    }

    private var filteredReceipts: [ReceiptStat] {
        let all = allReceipts
        guard !receiptSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(all.prefix(30))
        }

        let query = receiptSearchText.lowercased()
        return all.filter { receipt in
            receipt.searchableText.lowercased().contains(query)
        }
    }

    private var allReceipts: [ReceiptStat] {
        receiptManager.receipts.sorted { $0.date > $1.date }
    }

    private func ensureReceiptDataLoaded() async {
        guard showsReceiptSection else { return }

        await MainActor.run {
            isLoadingReceipts = true
        }

        await notesManager.ensureReceiptDataAvailable()
        await receiptManager.ensureLoaded()

        await MainActor.run {
            isLoadingReceipts = false
        }
    }

    private func persistChanges() {
        isSaving = true

        Task {
            let cleanedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch contentMode {
            case .full:
                await onSave(cleanedNotes)
                await peopleManager.linkPeopleToVisit(visitId: visit.id, personIds: Array(selectedPeopleIds))
                VisitReceiptLinkStore.setReceiptId(selectedReceiptNoteId, for: visit.id)
            case .noteOnly:
                await onSave(cleanedNotes)
            case .receiptOnly:
                VisitReceiptLinkStore.setReceiptId(selectedReceiptNoteId, for: visit.id)
                await onSave(cleanedNotes)
            }

            await MainActor.run {
                isSaving = false
                onDismiss()
            }
        }
    }

    private var timeRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let entryString = formatter.string(from: visit.entryTime)

        if let exitTime = visit.exitTime {
            let exitString = formatter.string(from: exitTime)
            return "\(entryString) - \(exitString)"
        } else {
            return entryString
        }
    }

    private func durationString(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }

    private func shortDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

enum VisitReceiptLinkStore {
    private static let storageKey = "VisitReceiptLinks.v1"

    static func allLinks() -> [UUID: UUID] {
        let raw = load()
        var mapped: [UUID: UUID] = [:]

        for (visitId, noteId) in raw {
            guard
                let visitUUID = UUID(uuidString: visitId),
                let noteUUID = UUID(uuidString: noteId)
            else { continue }
            mapped[visitUUID] = noteUUID
        }
        return mapped
    }

    static func receiptId(for visitId: UUID) -> UUID? {
        let links = load()
        guard let raw = links[visitId.uuidString] else { return nil }
        return UUID(uuidString: raw)
    }

    static func setReceiptId(_ receiptId: UUID?, for visitId: UUID) {
        var links = load()

        if let receiptId {
            links[visitId.uuidString] = receiptId.uuidString
        } else {
            links.removeValue(forKey: visitId.uuidString)
        }

        save(links)
        NotificationCenter.default.post(name: .visitReceiptLinkUpdated, object: visitId)
        Task { @MainActor in
            await VectorSearchService.shared.refreshVisitEmbeddingsIncremental(reason: "visit-receipt link update")
        }
    }

    private static func load() -> [String: String] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func save(_ links: [String: String]) {
        guard let encoded = try? JSONEncoder().encode(links) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}

extension Notification.Name {
    static let visitReceiptLinkUpdated = Notification.Name("VisitReceiptLinkUpdated")
}
