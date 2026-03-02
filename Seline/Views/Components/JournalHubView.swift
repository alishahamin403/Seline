import SwiftUI

private enum JournalHistoryItem: Identifiable {
    case entry(Note)
    case recap(Note)

    var id: UUID {
        note.id
    }

    var note: Note {
        switch self {
        case .entry(let note), .recap(let note):
            return note
        }
    }

    var sortDate: Date {
        switch self {
        case .entry(let note):
            return note.journalDate ?? note.dateModified
        case .recap(let note):
            return note.journalWeekStartDate ?? note.dateModified
        }
    }
}

struct JournalHubView: View {
    let openTodayOnAppear: Bool
    let onConsumeOpenToday: (() -> Void)?
    let scrollToHistoryOnAppear: Bool
    let onConsumeScrollToHistory: (() -> Void)?

    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var journalService = JournalService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var draftToOpen: JournalDraft? = nil
    @State private var existingNoteToOpen: Note? = nil
    @State private var hasHandledOpenTodayOnAppear = false
    @State private var hasHandledScrollToHistoryOnAppear = false
    @State private var isRefreshingRecap = false

    private var journalStats: JournalStats {
        journalService.stats(referenceDate: Date())
    }

    private var todayEntry: Note? {
        journalService.entryForToday()
    }

    private var latestRecap: Note? {
        journalService.latestRecap()
    }

    private var historyItems: [JournalHistoryItem] {
        let combined = notesManager.journalEntries.map { JournalHistoryItem.entry($0) } +
            notesManager.journalWeeklyRecaps.map { JournalHistoryItem.recap($0) }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty ? combined : combined.filter { item in
            item.note.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            item.note.content.localizedCaseInsensitiveContains(trimmedQuery)
        }

        return filtered.sorted { $0.sortDate > $1.sortDate }
    }

    private var promptTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = journalService.promptHour
                components.minute = journalService.promptMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                journalService.promptHour = components.hour ?? 21
                journalService.promptMinute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    heroCard
                    todayEntryCard
                    weeklyRecapCard
                    historyCard
                        .id("journal-history")

                    Spacer()
                        .frame(height: 60)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            .background(Color.appBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await journalService.ensureWeeklyRecapIfNeeded()
                    if journalService.isPromptEnabled {
                        await journalService.scheduleDailyPromptIfNeeded()
                    }
                }

                if openTodayOnAppear, !hasHandledOpenTodayOnAppear {
                    hasHandledOpenTodayOnAppear = true
                    onConsumeOpenToday?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        openTodayEntry()
                    }
                    return
                }

                guard scrollToHistoryOnAppear, !hasHandledScrollToHistoryOnAppear else { return }
                hasHandledScrollToHistoryOnAppear = true
                onConsumeScrollToHistory?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("journal-history", anchor: .top)
                    }
                }
            }
            .fullScreenCover(item: $existingNoteToOpen) { note in
                NoteEditView(
                    note: note,
                    isPresented: Binding(
                        get: { existingNoteToOpen != nil },
                        set: { if !$0 { existingNoteToOpen = nil } }
                    )
                )
            }
            .fullScreenCover(item: $draftToOpen) { draft in
                NoteEditView(
                    note: nil,
                    isPresented: Binding(
                        get: { draftToOpen != nil },
                        set: { if !$0 { draftToOpen = nil } }
                    ),
                    initialFolderId: draft.folderId,
                    initialTitle: draft.title,
                    initialNoteKind: draft.kind,
                    initialJournalDate: draft.journalDate
                )
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Journal")
                        .font(FontManager.geist(size: 28, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    Text("Daily writing inside Notes")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }

                Spacer(minLength: 12)

                Button(action: openTodayEntry) {
                    Image(systemName: todayEntry == nil ? "square.and.pencil" : "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundColor(.black)
                        .background(
                            Circle()
                                .fill(Color(red: 0.98, green: 0.64, blue: 0.41))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 10) {
                journalMetricTile(title: "Prompt", value: journalService.formatPromptTime())
                journalMetricTile(title: "Streak", value: "\(journalStats.currentStreak)d")
                journalMetricTile(title: "This week", value: "\(journalStats.completedThisWeek) / 7")
            }

            HStack(spacing: 12) {
                Toggle(isOn: $journalService.isPromptEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily prompt")
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                        Text(journalService.isPromptEnabled ? "Notification and in-app reminder are on" : "In-app reminder only")
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                }
                .tint(Color(red: 0.98, green: 0.64, blue: 0.41))
            }

            DatePicker(
                "Prompt time",
                selection: promptTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .font(FontManager.geist(size: 14, weight: .medium))
            .foregroundColor(Color.appTextPrimary(colorScheme))
        }
        .padding(16)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 16,
            x: 0,
            y: 6
        )
    }

    private var todayEntryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                    Text(todayEntry == nil ? "No entry saved yet" : "You can reopen and add more")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
                Spacer()
                statusPill(
                    text: journalStats.todayStatus == .complete ? "Done today" : "Today missing",
                    isPositive: journalStats.todayStatus == .complete
                )
            }

            Button(action: openTodayEntry) {
                HStack(spacing: 10) {
                    Image(systemName: todayEntry == nil ? "square.and.pencil" : "doc.text")
                        .font(.system(size: 15, weight: .medium))
                    Text(todayEntry == nil ? "Write today's entry" : "Open today's entry")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.appInnerSurface(colorScheme))
                )
            }
            .buttonStyle(PlainButtonStyle())

            if let todayEntry {
                Text(todayEntry.preview)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(4)
            } else {
                Text("Capture what stood out, what drained you, or what you want to carry into tomorrow.")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }
        }
        .padding(16)
        .background(sectionCardBackground)
    }

    private var weeklyRecapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Recap")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                    Text("Saved summaries of the overall week")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
                Spacer()

                Button(action: refreshRecap) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isRefreshingRecap ? "Checking" : "Refresh")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.appInnerSurface(colorScheme))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshingRecap)
            }

            if let latestRecap {
                recapPreview(note: latestRecap)
            } else {
                Text("No weekly recap yet. Once you have enough entries for a completed week, Seline will save one here.")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }
        }
        .padding(16)
        .background(sectionCardBackground)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("History")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))

                TextField("Search journal history", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appInnerSurface(colorScheme))
            )

            if historyItems.isEmpty {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No journal history yet" : "No matching journal items")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .padding(.top, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(historyItems) { item in
                        historyRow(item)
                    }
                }
            }
        }
        .padding(16)
        .background(sectionCardBackground)
    }

    private func historyRow(_ item: JournalHistoryItem) -> some View {
        Button(action: {
            existingNoteToOpen = item.note
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.note.title)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .lineLimit(1)

                        if item.note.isJournalWeeklyRecap {
                            statusPill(text: "Recap", isPositive: false)
                        }
                    }

                    Text(item.note.preview)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text(historyDateLabel(for: item))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appInnerSurface(colorScheme))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func recapPreview(note: Note) -> some View {
        Button(action: {
            existingNoteToOpen = note
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusPill(text: "Saved recap", isPositive: false)
                    Spacer()
                    Text(historyDateLabel(for: .recap(note)))
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }

                Text(note.title)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)

                Text(note.preview)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appInnerSurface(colorScheme))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func journalMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            Text(value)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appInnerSurface(colorScheme))
        )
    }

    private func statusPill(text: String, isPositive: Bool) -> some View {
        Text(text)
            .font(FontManager.geist(size: 12, weight: .semibold))
            .foregroundColor(isPositive ? Color(red: 0.13, green: 0.48, blue: 0.23) : Color(red: 0.22, green: 0.37, blue: 0.67))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isPositive ? Color(red: 0.87, green: 0.96, blue: 0.88) : Color(red: 0.88, green: 0.92, blue: 1.0))
            )
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.appSurface(colorScheme))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color(red: 0.98, green: 0.64, blue: 0.41).opacity(colorScheme == .dark ? 0.14 : 0.22))
                    .frame(width: 220, height: 220)
                    .blur(radius: 8)
                    .offset(x: 60, y: -48)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5))
                    .frame(width: 220, height: 220)
                    .blur(radius: 12)
                    .offset(x: -24, y: 90)
            }
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.appSectionCard(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
    }

    private func historyDateLabel(for item: JournalHistoryItem) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = item.note.isJournalWeeklyRecap ? "MMM d" : "EEE"
        let sourceDate = item.note.isJournalWeeklyRecap ? (item.note.journalWeekStartDate ?? item.note.dateModified) : (item.note.journalDate ?? item.note.dateModified)
        return formatter.string(from: sourceDate)
    }

    private func openTodayEntry() {
        if let entry = todayEntry {
            existingNoteToOpen = entry
        } else {
            Task {
                draftToOpen = await journalService.prepareTodayDraftEnsuringFolder()
            }
        }
    }

    private func refreshRecap() {
        guard !isRefreshingRecap else { return }
        isRefreshingRecap = true
        Task {
            await journalService.ensureWeeklyRecapIfNeeded()
            await MainActor.run {
                isRefreshingRecap = false
            }
        }
    }
}
