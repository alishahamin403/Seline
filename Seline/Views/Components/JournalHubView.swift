import SwiftUI

struct JournalHubView: View {
    let openTodayOnAppear: Bool
    let onConsumeOpenToday: (() -> Void)?
    let scrollToHistoryOnAppear: Bool
    let onConsumeScrollToHistory: (() -> Void)?
    let isEmbeddedInNotesShell: Bool

    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var journalService = JournalService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftToOpen: JournalDraft? = nil
    @State private var existingNoteToOpen: Note? = nil
    @State private var hasHandledOpenTodayOnAppear = false
    @State private var hasHandledScrollToHistoryOnAppear = false
    @State private var showingPreviousRecaps = false
    @State private var visibleHistoryMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedHistoryDate = Calendar.current.startOfDay(for: Date())

    private var journalStats: JournalStats {
        journalService.stats(referenceDate: Date())
    }

    private var todayEntry: Note? {
        journalService.entryForToday()
    }

    private var currentWeekStart: Date? {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date()).map {
            Calendar.current.startOfDay(for: $0.start)
        }
    }

    private var currentWeekMeaningfulEntries: [Note] {
        guard let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return notesManager.meaningfulJournalEntries
            .filter { entry in
                guard let journalDate = entry.journalDate else { return false }
                return weekInterval.contains(journalDate)
            }
            .sorted { ($0.journalDate ?? $0.dateModified) < ($1.journalDate ?? $1.dateModified) }
    }

    private var currentWeekJournalFingerprint: String {
        currentWeekMeaningfulEntries.map { entry in
            let journalDate = entry.journalDate ?? entry.dateModified
            let normalizedDate = Calendar.current.startOfDay(for: journalDate).timeIntervalSince1970
            let trimmedContent = entry.displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let mood = entry.journalMood?.rawValue ?? ""
            return "\(entry.id.uuidString)|\(normalizedDate)|\(entry.dateModified.timeIntervalSince1970)|\(mood)|\(trimmedContent)"
        }
        .joined(separator: "\n")
    }

    private var currentWeekRecap: Note? {
        guard let currentWeekStart, !currentWeekMeaningfulEntries.isEmpty else { return nil }
        return notesManager.journalWeeklyRecaps.first { recap in
            guard let recapWeekStart = recap.journalWeekStartDate else { return false }
            return Calendar.current.isDate(recapWeekStart, inSameDayAs: currentWeekStart)
        }
    }

    private var previousWeekRecaps: [Note] {
        guard let currentWeekStart else { return notesManager.journalWeeklyRecaps }
        return notesManager.journalWeeklyRecaps.filter { recap in
            guard let recapWeekStart = recap.journalWeekStartDate else { return true }
            return !Calendar.current.isDate(recapWeekStart, inSameDayAs: currentWeekStart)
        }
    }

    private var currentMonthStart: Date {
        monthStart(for: Date())
    }

    private var oldestHistoryMonth: Date {
        let oldestJournalDate = notesManager.journalEntries.last.map { $0.journalDate ?? $0.dateModified } ?? Date()
        return monthStart(for: oldestJournalDate)
    }

    private var visibleHistoryMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleHistoryMonth)
    }

    private var canShowOlderHistoryMonth: Bool {
        visibleHistoryMonth > oldestHistoryMonth
    }

    private var canShowNewerHistoryMonth: Bool {
        !Calendar.current.isDate(visibleHistoryMonth, equalTo: currentMonthStart, toGranularity: .month)
    }

    private var historyWeekdaySymbols: [String] {
        ["S", "M", "T", "W", "T", "F", "S"]
    }

    private var historyCalendarWeeks: [[Date?]] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleHistoryMonth) else { return [] }
        let firstDay = calendar.startOfDay(for: monthInterval.start)
        let weekdayIndex = calendar.component(.weekday, from: firstDay)
        let leadingEmptyDays = (weekdayIndex - calendar.firstWeekday + 7) % 7

        var dates: [Date?] = Array(repeating: nil, count: leadingEmptyDays)

        var current = firstDay
        let monthEnd = calendar.startOfDay(for: monthInterval.end)
        while current < monthEnd {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        while dates.count % 7 != 0 {
            dates.append(nil)
        }

        return stride(from: 0, to: dates.count, by: 7).map { index in
            Array(dates[index..<min(index + 7, dates.count)])
        }
    }

    private var selectedHistoryEntry: Note? {
        notesManager.meaningfulJournalEntry(for: selectedHistoryDate)
    }

    private var selectedHistoryDateIsMissing: Bool {
        selectedHistoryEntry == nil && shouldShowMissingIndicator(for: selectedHistoryDate)
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
        Group {
            if isEmbeddedInNotesShell {
                journalContent
            } else {
                journalContent
                    .navigationTitle("Journal")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var journalContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    heroCard
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
            .onAppear {
                Task {
                    await journalService.ensureWeeklyRecapIfNeeded(forceRefreshCurrentWeek: true)
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
            .onChange(of: currentWeekJournalFingerprint) { _ in
                Task {
                    await journalService.ensureWeeklyRecapIfNeeded(forceRefreshCurrentWeek: true)
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
            .sheet(isPresented: $showingPreviousRecaps) {
                previousRecapsSheet
                    .presentationBg()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: isEmbeddedInNotesShell ? 0 : 4) {
                    if !isEmbeddedInNotesShell {
                        Text("Journal")
                            .font(FontManager.geist(size: 28, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }
                    Text("Daily writing inside Notes")
                        .font(
                            FontManager.geist(
                                size: isEmbeddedInNotesShell ? 14 : 13,
                                weight: isEmbeddedInNotesShell ? .medium : .regular
                            )
                        )
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

    private var weeklyRecapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly Recap")
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        showingPreviousRecaps = true
                    }) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.appInnerSurface(colorScheme))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(previousWeekRecaps.isEmpty)
                    .opacity(previousWeekRecaps.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Previous recaps")
                }
            }

            if let currentWeekRecap {
                recapPreview(note: currentWeekRecap)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let currentWeekStart {
                        Text(weekRangeTitle(for: currentWeekStart))
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .lineLimit(1)
                    }

                    Text("No recap for this week yet. Add journal entries and Seline will keep this summary updated as the week progresses.")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.appInnerSurface(colorScheme))
                )
            }
        }
        .padding(16)
        .background(sectionCardBackground)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            historyCalendarCard
            historySelectedDayCard
        }
    }

    private var historyCalendarCard: some View {
        VStack(spacing: 0) {
            historyMonthNavigator
            historyWeekdayHeader
            historyMonthGrid
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 24,
            highlightStrength: 0.58
        )
    }

    private var historyMonthNavigator: some View {
        HStack {
            Button(action: { shiftHistoryMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(canShowOlderHistoryMonth ? 1 : 0.35))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canShowOlderHistoryMonth)
            .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.selection() })

            Spacer()

            Text(visibleHistoryMonthTitle)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            Button(action: jumpToCurrentHistoryMonth) {
                Text("Today")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { shiftHistoryMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(canShowNewerHistoryMonth ? 1 : 0.35))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canShowNewerHistoryMonth)
            .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.selection() })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var historyWeekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(historyWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var historyMonthGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(historyCalendarWeeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            historyCalendarDayCell(for: date, in: visibleHistoryMonth)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 58)
            }
        }
        .padding(.bottom, 10)
    }

    private func historyCalendarDayCell(for date: Date, in month: Date) -> some View {
        let note = notesManager.meaningfulJournalEntry(for: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedHistoryDate)
        let isToday = Calendar.current.isDateInToday(date)
        let isMissing = note == nil && shouldShowMissingIndicator(for: date)
        let isInCurrentMonth = Calendar.current.isDate(date, equalTo: month, toGranularity: .month)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedHistoryDate = Calendar.current.startOfDay(for: date)
            }
            HapticManager.shared.selection()
        }) {
            VStack(spacing: 5) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(FontManager.geist(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? .black : .white) :
                        isMissing && isInCurrentMonth ? journalAccentColor :
                        !isInCurrentMonth ? (colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35)) :
                        (colorScheme == .dark ? Color.white : Color.black)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(colorScheme == .dark ? Color.white : Color.black)
                            } else if isToday {
                                Circle().stroke(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3), lineWidth: 1.5)
                            }
                        }
                    )

                if let mood = note?.journalMood {
                    Text(calendarMoodLabel(for: mood))
                        .font(FontManager.geist(size: 8, weight: .medium))
                        .foregroundColor(
                            isSelected
                            ? (colorScheme == .dark ? .black : .white)
                            : (colorScheme == .dark ? Color.white.opacity(0.74) : Color.black.opacity(0.72))
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                    ? (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                                    : (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                )
                        )
                } else if isMissing {
                    Circle()
                        .fill(journalAccentColor)
                        .frame(width: 6, height: 6)
                        .frame(height: 12)
                } else {
                    Color.clear
                        .frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var historySelectedDayCard: some View {
        if let selectedHistoryEntry {
            historyEntryRow(note: selectedHistoryEntry, previewLineLimit: 3)
        } else if selectedHistoryDateIsMissing {
            let hasExistingDraft = notesManager.journalEntry(for: selectedHistoryDate) != nil
            Button(action: {
                openDraftOrContinueEntry(for: selectedHistoryDate)
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(formattedHistoryDayTitle(for: selectedHistoryDate))
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text("Missing")
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(journalAccentColor)
                            )

                        Spacer()
                    }

                    Text(hasExistingDraft
                         ? "This day still needs a finished journal entry. Continue it to fill the gap."
                         : "No journal entry yet for this day. Open a draft to fill the gap.")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))

                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text(hasExistingDraft ? "Continue entry" : "Open draft")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.appInnerSurface(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(journalAccentColor.opacity(colorScheme == .dark ? 0.55 : 0.9), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(formattedHistoryDayTitle(for: selectedHistoryDate))
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text("No journal entry for this day yet.")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appInnerSurface(colorScheme))
            )
        }
    }

    private func historyEntryRow(note: Note, previewLineLimit: Int = 2) -> some View {
        Button(action: {
            existingNoteToOpen = note
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(note.title)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .lineLimit(1)

                        if let mood = note.journalMood {
                            moodPill(mood)
                        }
                    }

                    Text(note.preview)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(previewLineLimit)
                }

                Spacer(minLength: 12)

                Text(historyDateLabel(for: note))
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

    private func moodPill(_ mood: JournalMood) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mood.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(mood.title)
                .font(FontManager.geist(size: 11, weight: .semibold))
        }
        .foregroundColor(Color.appTextPrimary(colorScheme))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.appChip(colorScheme))
        )
        .overlay(
            Capsule()
                .stroke(Color.appBorder(colorScheme), lineWidth: 0.8)
        )
    }

    private func recapPreview(note: Note) -> some View {
        Button(action: {
            existingNoteToOpen = note
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.title)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)

                Text(recapPreviewText(for: note))
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(6)
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

    private var previousRecapsSheet: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if previousWeekRecaps.isEmpty {
                        Text("No previous weekly recaps yet")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(previousWeekRecaps, id: \.id) { recap in
                            Button {
                                showingPreviousRecaps = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    existingNoteToOpen = recap
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(recap.title)
                                        .font(FontManager.geist(size: 15, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(recapPreviewText(for: recap))
                                        .font(FontManager.geist(size: 14, weight: .regular))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .multilineTextAlignment(.leading)
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
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("Previous Recaps")
            .navigationBarTitleDisplayMode(.inline)
        }
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

    private var journalAccentColor: Color {
        Color(red: 0.98, green: 0.64, blue: 0.41)
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.appSurface(colorScheme))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(journalAccentColor.opacity(colorScheme == .dark ? 0.14 : 0.22))
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

    private func historyDateLabel(for note: Note) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let sourceDate = note.journalDate ?? note.dateModified
        return formatter.string(from: sourceDate)
    }

    private func formattedHistoryDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private func recapPreviewText(for note: Note) -> String {
        let trimmed = note.displayContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "No recap details yet." }
        return String(trimmed.prefix(260))
    }

    private func calendarMoodLabel(for mood: JournalMood) -> String {
        switch mood {
        case .great: return "Great"
        case .good: return "Good"
        case .calm: return "Calm"
        case .tired: return "Tired"
        case .stressed: return "Stress"
        case .low: return "Low"
        }
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: date)
        ) ?? Calendar.current.startOfDay(for: date)
    }

    private func shouldShowMissingIndicator(for date: Date) -> Bool {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        return normalizedDate < today
    }

    private func shiftHistoryMonth(by offset: Int) {
        guard let shiftedMonth = Calendar.current.date(byAdding: .month, value: offset, to: visibleHistoryMonth) else {
            return
        }

        let normalizedMonth = monthStart(for: shiftedMonth)
        visibleHistoryMonth = normalizedMonth

        if Calendar.current.isDate(normalizedMonth, equalTo: currentMonthStart, toGranularity: .month) {
            selectedHistoryDate = Calendar.current.startOfDay(for: Date())
        } else {
            selectedHistoryDate = normalizedMonth
        }
    }

    private func jumpToCurrentHistoryMonth() {
        visibleHistoryMonth = currentMonthStart
        selectedHistoryDate = Calendar.current.startOfDay(for: Date())
        HapticManager.shared.selection()
    }

    private func weekRangeTitle(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Weekly Recap • \(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    private func openDraft(for date: Date) {
        Task {
            draftToOpen = await journalService.prepareDraftEnsuringFolder(for: date)
        }
    }

    private func openDraftOrContinueEntry(for date: Date) {
        if let existingEntry = notesManager.journalEntry(for: date) {
            existingNoteToOpen = existingEntry
        } else {
            openDraft(for: date)
        }
    }

    private func openTodayEntry() {
        if let entry = todayEntry {
            existingNoteToOpen = entry
        } else {
            openDraft(for: Date())
        }
    }
}
