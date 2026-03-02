import SwiftUI
import PostgREST

struct LocationTimelineView: View {
    let colorScheme: ColorScheme

    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var peopleManager = PeopleManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var visitState = VisitStateManager.shared

    @State private var isLoading = false
    @State private var selectedPlace: SavedPlace? = nil
    
    // Merge mode state
    @State private var isMergeMode = false
    @State private var selectedVisitsForMerge: [UUID] = []
    @State private var isMerging = false
    @State private var showMergeError = false
    @State private var mergeErrorMessage = ""
    @State private var selectedVisitForNotes: LocationVisitRecord? = nil
    @State private var selectedVisitForPeople: LocationVisitRecord? = nil
    @State private var visitPeopleCache: [UUID: [Person]] = [:] // Cache people for each visit
    @State private var showDeleteConfirmation = false
    @State private var visitToDelete: LocationVisitRecord? = nil
    @State private var reloadTask: Task<Void, Never>?
    @State private var monthPageSelection: Int = 1
    @State private var monthVisitLabels: [Date: String] = [:]
    @State private var linkedReceiptIds: [UUID: UUID] = [:]

    private let calendar = Calendar.current
    private let calendarRowHeight: CGFloat = 58

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private struct MonthVisitLabelData: Codable {
        let savedPlaceId: UUID
        let entryTime: Date

        enum CodingKeys: String, CodingKey {
            case savedPlaceId = "saved_place_id"
            case entryTime = "entry_time"
        }
    }

    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .bottomTrailing)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    calendarSection

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else if visitState.selectedDayVisits.isEmpty {
                        emptyDayView
                    } else {
                        timelineSection
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .onAppear {
            refreshLinkedReceiptLinks()
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
            // Debounce: Cancel previous reload and schedule new one
            reloadTask?.cancel()
            reloadTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if !Task.isCancelled {
                    loadVisitsForMonth()
                    loadVisitsForSelectedDay()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VisitHistoryUpdated"))) { _ in
            reloadTask?.cancel()
            reloadTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    // Invalidate cache
                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "yyyy-MM-dd"
                    let dayKey = dayFormatter.string(from: visitState.selectedDate)
                    CacheManager.shared.invalidate(forKey: "cache.visits.day.\(dayKey)")

                    loadVisitsForMonth()
                    loadVisitsForSelectedDay()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .visitReceiptLinkUpdated)) { _ in
            refreshLinkedReceiptLinks()
        }
        .onChange(of: visitState.selectedDate) { _ in
            // Reload visits when selected date changes
            loadVisitsForSelectedDay()
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place, onDismiss: { 
                selectedPlace = nil
            })
            .presentationBg()
        }
        .sheet(item: $selectedVisitForNotes) { visit in
            VisitNotesSheet(
                visit: visit,
                place: locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }),
                colorScheme: colorScheme,
                onSave: { notes in
                    await saveVisitNotes(visit: visit, notes: notes)
                    selectedVisitForNotes = nil
                },
                onDismiss: {
                    selectedVisitForNotes = nil
                }
            )
            .presentationBg()
        }
        .sheet(item: $selectedVisitForPeople) { visit in
            VisitPeoplePickerSheet(
                visit: visit,
                colorScheme: colorScheme,
                onSave: { personIds in
                    Task {
                        await peopleManager.linkPeopleToVisit(
                            visitId: visit.id,
                            personIds: personIds
                        )
                        await loadPeopleForVisits([visit])
                    }
                },
                onDismiss: {
                    selectedVisitForPeople = nil
                }
            )
            .presentationBg()
        }
        .confirmationDialog("Delete Visit", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let visit = visitToDelete else { return }
                Task {
                    let success = await visitState.deleteVisit(id: visit.id)
                    if success {
                        HapticManager.shared.success()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this visit? This action cannot be undone.")
        }
    }

    // MARK: - Calendar Section

    @ViewBuilder
    private var calendarSection: some View {
        VStack(spacing: 0) {
            calendarMonthHeader
            calendarWeekdayHeader
            swipeableMonthGrid
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 24,
            highlightStrength: 0.58
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 12)
    }

    private var calendarMonthHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.26)) {
                    shiftMonth(by: -1)
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text(dateFormatter.string(from: visitState.currentMonth))
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.26)) {
                    let today = calendar.startOfDay(for: Date())
                    visitState.currentMonth = today
                    visitState.selectedDate = today
                    monthPageSelection = 1
                }
                HapticManager.shared.selection()
                loadVisitsForMonth()
                loadVisitsForSelectedDay()
            }) {
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

            Button(action: {
                withAnimation(.easeInOut(duration: 0.26)) {
                    shiftMonth(by: 1)
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var calendarWeekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var swipeableMonthGrid: some View {
        TabView(selection: $monthPageSelection) {
            calendarMonthGrid(for: monthOffset(-1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(-1)).count) * calendarRowHeight, alignment: .top)
                .tag(0)

            calendarMonthGrid(for: visitState.currentMonth)
                .frame(height: CGFloat(weeksInMonth(for: visitState.currentMonth).count) * calendarRowHeight, alignment: .top)
                .tag(1)

            calendarMonthGrid(for: monthOffset(1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(1)).count) * calendarRowHeight, alignment: .top)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: CGFloat(weeksInMonth(for: visitState.currentMonth).count) * calendarRowHeight)
        .padding(.bottom, 10)
        .onChange(of: monthPageSelection) { newSelection in
            guard newSelection != 1 else { return }

            withAnimation(.easeInOut(duration: 0.26)) {
                if newSelection == 0 {
                    shiftMonth(by: -1)
                } else {
                    shiftMonth(by: 1)
                }
            }

            DispatchQueue.main.async {
                monthPageSelection = 1
            }
        }
    }

    private func calendarMonthGrid(for month: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(weeksInMonth(for: month).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            calendarDayCell(for: date, in: month)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: calendarRowHeight)
            }
        }
    }

    @ViewBuilder
    private func calendarDayCell(for date: Date, in month: Date) -> some View {
        let normalizedDate = normalizeDate(date)
        let isSelected = calendar.isDate(date, inSameDayAs: visitState.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let visitCount = visitState.monthVisitCounts[normalizedDate] ?? 0
        let hasVisits = visitCount > 0
        let visitLabel = monthVisitLabels[normalizedDate]
        let isInCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)

        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                visitState.selectedDate = normalizedDate
            }
            loadVisitsForSelectedDay()
            HapticManager.shared.selection()
        }) {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(FontManager.geist(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? .black : .white) :
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

                if hasVisits, let visitLabel {
                    Text(visitLabel)
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

    // MARK: - Timeline Section

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .center) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDayString())
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("\(visitState.selectedDayVisits.count) visit\(visitState.selectedDayVisits.count == 1 ? "" : "s")")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(totalTimeString())
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("total time")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
                    }
                }

                if visitState.selectedDayVisits.count >= 2 || isMergeMode {
                    mergeModeToggleButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Merge mode instructions
            if isMergeMode {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    
                    Text(selectedVisitsForMerge.count == 0 ? "Tap the first visit" :
                         selectedVisitsForMerge.count == 1 ? "Tap the second visit to merge with" :
                         "Ready to merge")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    
                    Spacer()
                    
                    if selectedVisitsForMerge.count == 2 {
                        Button(action: {
                            performMerge()
                        }) {
                            HStack(spacing: 4) {
                                if isMerging {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(colorScheme == .dark ? .white : .black)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                Text("Merge")
                                    .font(FontManager.geist(size: 13, weight: .semibold))
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isMerging)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
            }

            // Visit cards
            LazyVStack(spacing: 12) {
                ForEach(visitState.selectedDayVisits.sorted(by: { $0.entryTime < $1.entryTime })) { visit in
                    visitCard(for: visit)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .bottomLeading,
            cornerRadius: 28,
            highlightStrength: 0.54
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.vertical, 12)
        .alert("Merge Failed", isPresented: $showMergeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mergeErrorMessage)
        }
    }

    private var mergeModeToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isMergeMode.toggle()
                if !isMergeMode {
                    selectedVisitsForMerge.removeAll()
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isMergeMode ? "xmark.circle.fill" : "arrow.triangle.merge")
                    .font(.system(size: 12, weight: .medium))
                Text(isMergeMode ? "Cancel" : "Merge")
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .foregroundColor(
                isMergeMode
                ? .red
                : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isMergeMode
                        ? Color.red.opacity(0.15)
                        : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func visitCard(for visit: LocationVisitRecord) -> some View {
        if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
            let isSelectedForMerge = selectedVisitsForMerge.contains(visit.id)
            let linkedReceipt = linkedReceipt(for: visit)
            
            Button(action: {
                if isMergeMode {
                    handleMergeSelection(visit: visit)
                } else {
                    // Long press to add notes, tap to view place details
                    selectedPlace = place
                }
            }) {
                HStack(spacing: 12) {
                    // Visit card - cleaner design without stroke overlay
                    HStack(spacing: 12) {
                        PlaceImageView(place: place, size: 40, cornerRadius: ShadcnRadius.lg)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.displayName)
                                .font(FontManager.geist(size: 14, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(place.category)
                                    .font(FontManager.geist(size: 11, weight: .medium))
                                    .foregroundColor(categoryColor(for: place.category))
                                    .lineLimit(1)
                            }

                            HStack(spacing: 6) {
                                Text(timeRangeString(from: visit))
                                    .font(FontManager.geist(size: 11, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                    .lineLimit(1)

                                if let duration = visit.durationMinutes {
                                    Text("•")
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))

                                    Text(durationString(minutes: duration))
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                            
                            // Show visit notes if exists (limited to 2 lines, tap note icon for full text)
                            if let notes = visit.visitNotes, !notes.isEmpty {
                                Text(notes)
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                    .italic()
                                    .lineLimit(2)
                                    .padding(.top, 4)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: -6) {
                                    if let people = visitPeopleCache[visit.id], !people.isEmpty {
                                        ForEach(people.prefix(4)) { person in
                                            Circle()
                                                .fill(colorForRelationship(person.relationship))
                                                .frame(width: 22, height: 22)
                                                .overlay(
                                                    Text(person.initials)
                                                        .font(FontManager.geist(size: 8, weight: .semibold))
                                                        .foregroundColor(.white)
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1.5)
                                                )
                                        }

                                        if people.count > 4 {
                                            Circle()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                                .frame(width: 22, height: 22)
                                                .overlay(
                                                    Text("+\(people.count - 4)")
                                                        .font(FontManager.geist(size: 8, weight: .semibold))
                                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1.5)
                                                )
                                        }

                                        Text("with \(people.map { $0.displayName }.prefix(2).joined(separator: ", "))\(people.count > 2 ? "..." : "")")
                                            .font(FontManager.geist(size: 10, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                            .padding(.leading, 8)
                                    }
                                }

                                if let linkedReceipt {
                                    HStack(spacing: 6) {
                                        Image(systemName: "receipt.fill")
                                            .font(FontManager.geist(size: 9, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))

                                        Text(linkedReceipt.title)
                                            .font(FontManager.geist(size: 10, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                    )
                                }
                            }
                            .padding(.top, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isMergeMode, let people = visitPeopleCache[visit.id], !people.isEmpty {
                                    selectedVisitForPeople = visit
                                }
                            }
                        }

                        Spacer()
                        
                        // Merge selection indicator or Notes button
                        if isMergeMode {
                            ZStack {
                                if isSelectedForMerge {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white : Color.black)
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .black : .white)
                                } else {
                                    Circle()
                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                // Show note icon if visit has notes, calendar+ icon if no notes
                                if let notes = visit.visitNotes, !notes.isEmpty {
                                    // Has notes - show note icon to view
                                    Button(action: {
                                        selectedVisitForNotes = visit
                                    }) {
                                        Image(systemName: "note.text")
                                            .font(FontManager.geist(size: 16, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.75))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else {
                                    // No notes - show calendar+ icon to add notes
                                    Button(action: {
                                        selectedVisitForNotes = visit
                                    }) {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(FontManager.geist(size: 16, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }

                                // Delete button
                                Button(action: {
                                    visitToDelete = visit
                                    showDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash.fill")
                                        .font(FontManager.geist(size: 14, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                            .fill(Color.shadcnTileBackground(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                            .stroke(
                                isSelectedForMerge ? 
                                (colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)) : 
                                Color.clear, 
                                lineWidth: isSelectedForMerge ? 1.5 : 0
                            )
                    )
                    .scaleEffect(isSelectedForMerge ? 1.02 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelectedForMerge)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private var emptyDayView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(FontManager.geist(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

            Text("No visits on this day")
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

            Text("Visit saved locations to see them here")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Functions

    private func weeksInMonth(for month: Date) -> [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }

        let firstDay = calendar.startOfDay(for: monthInterval.start)
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        var current = firstDay
        let monthEnd = calendar.startOfDay(for: monthInterval.end)

        while current < monthEnd {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    private func monthOffset(_ value: Int) -> Date {
        calendar.date(byAdding: .month, value: value, to: visitState.currentMonth) ?? visitState.currentMonth
    }

    private func shiftMonth(by value: Int) {
        visitState.currentMonth = calendar.date(byAdding: .month, value: value, to: visitState.currentMonth) ?? visitState.currentMonth
        loadVisitsForMonth()
    }

    private func normalizeDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private func selectedDayString() -> String {
        let formatter = DateFormatter()
        if calendar.isDateInToday(visitState.selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(visitState.selectedDate) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: visitState.selectedDate)
        }
    }

    private func visitSummary() -> String {
        let count = visitState.selectedDayVisits.count
        let totalMinutes = visitState.selectedDayVisits.compactMap { $0.durationMinutes }.reduce(0, +)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(count) visit\(count == 1 ? "" : "s") • \(hours)h \(minutes)m"
        } else {
            return "\(count) visit\(count == 1 ? "" : "s") • \(minutes)m"
        }
    }

    private func totalTimeString() -> String {
        let totalMinutes = visitState.selectedDayVisits.compactMap { $0.durationMinutes }.reduce(0, +)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func timeRangeString(from visit: LocationVisitRecord) -> String {
        // Use same time formatting as VisitHistoryCard for consistency
        let formatter = DateFormatter()
        formatter.timeStyle = .short  // Uses system locale format (same as VisitHistoryCard)

        let entryString = formatter.string(from: visit.entryTime)

        if let exitTime = visit.exitTime {
            let exitString = formatter.string(from: exitTime)
            return "\(entryString) - \(exitString)"
        } else {
            return "Started at \(entryString)"  // Same format as VisitHistoryCard
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
    
    private func saveVisitNotes(visit: LocationVisitRecord, notes: String) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            let updateData: [String: PostgREST.AnyJSON] = [
                "visit_notes": .string(notes),
                "updated_at": .string(formatter.string(from: Date()))
            ]
            
            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visit.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
            
            // Reload visits to show updated notes
            await loadVisitsForSelectedDay()
        } catch {
            print("❌ Failed to save visit notes: \(error)")
        }
    }

    // MARK: - Merge Functions
    
    private func handleMergeSelection(visit: LocationVisitRecord) {
        // If already selected, deselect
        if let index = selectedVisitsForMerge.firstIndex(of: visit.id) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedVisitsForMerge.remove(at: index)
            }
            return
        }
        
        // If we already have 2 selected, show error
        if selectedVisitsForMerge.count >= 2 {
            return
        }
        
        // Check if this visit is at the same location as the first selected visit
        if let firstVisitId = selectedVisitsForMerge.first,
           let firstVisit = visitState.selectedDayVisits.first(where: { $0.id == firstVisitId }) {
            if firstVisit.savedPlaceId != visit.savedPlaceId {
                mergeErrorMessage = "You can only merge visits at the same location"
                showMergeError = true
                return
            }
        }
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            selectedVisitsForMerge.append(visit.id)
        }
        
        // Debug: Log selected visit ID
        print("🔀 Selected visit for merge: ID=\(visit.id), Place=\(visit.savedPlaceId), Entry=\(visit.entryTime)")
        
        // Haptic feedback
        HapticManager.shared.selection()
    }
    
    private func performMerge() {
        guard selectedVisitsForMerge.count == 2 else { return }
        
        let firstVisitId = selectedVisitsForMerge[0]
        let secondVisitId = selectedVisitsForMerge[1]
        
        // Find the visits
        guard let firstVisit = visitState.selectedDayVisits.first(where: { $0.id == firstVisitId }),
              let secondVisit = visitState.selectedDayVisits.first(where: { $0.id == secondVisitId }) else {
            mergeErrorMessage = "Could not find selected visits in current view"
            showMergeError = true
            return
        }
        
        // Determine which is earlier and which is later
        let (earlierVisitId, laterVisitId) = firstVisit.entryTime < secondVisit.entryTime
            ? (firstVisitId, secondVisitId)
            : (secondVisitId, firstVisitId)
        
        isMerging = true
        
        Task {
            // Invalidate cache before merge to ensure we're working with fresh data
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let dayKey = dayFormatter.string(from: visitState.selectedDate)
            CacheManager.shared.invalidate(forKey: "cache.visits.day.\(dayKey)")
            
            let success = await LocationVisitAnalytics.shared.manualMergeVisits(
                firstVisitId: earlierVisitId,
                secondVisitId: laterVisitId
            )
            
            await MainActor.run {
                isMerging = false
                
                if success {
                    HapticManager.shared.success()
                    
                    // Reset merge mode
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isMergeMode = false
                        selectedVisitsForMerge.removeAll()
                    }
                    
                    // Reload visits (cache already invalidated)
                    loadVisitsForSelectedDay()
                    loadVisitsForMonth()
                } else {
                    HapticManager.shared.error()
                    mergeErrorMessage = LocationVisitAnalytics.shared.errorMessage ?? "Failed to merge visits"
                    showMergeError = true
                }
            }
        }
    }

    private func categoryColor(for category: String) -> Color {
        // Simple color mapping based on category
        switch category.lowercased() {
        case let c where c.contains("restaurant") || c.contains("food"):
            return Color.primary
        case let c where c.contains("coffee") || c.contains("cafe"):
            return Color.brown
        case let c where c.contains("gym") || c.contains("fitness"):
            return Color.red
        case let c where c.contains("shop") || c.contains("store"):
            return Color.purple
        case let c where c.contains("park") || c.contains("nature"):
            return Color.green
        case let c where c.contains("entertainment") || c.contains("movie"):
            return Color.pink
        default:
            return Color.blue
        }
    }

    // MARK: - Data Loading

    private func loadVisitsForMonth() {
        Task {
            // Use centralized state manager
            await visitState.fetchVisitsForMonth(visitState.currentMonth)
            await loadMonthVisitLabels(for: visitState.currentMonth)
        }
    }

    private func loadVisitsForSelectedDay() {
        Task {
            await MainActor.run {
                isLoading = true
            }

            // Use centralized state manager
            await visitState.fetchVisitsForDay(visitState.selectedDate)

            await MainActor.run {
                isLoading = false
            }

            // Load people for each visit
            await loadPeopleForVisits(visitState.selectedDayVisits)
        }
    }
    
    // MARK: - Load People for Visits

    private func loadPeopleForVisits(_ visits: [LocationVisitRecord]) async {
        await withTaskGroup(of: (UUID, [Person]).self) { group in
            for visit in visits {
                group.addTask {
                    let people = await self.peopleManager.getPeopleForVisit(visitId: visit.id)
                    return (visit.id, people)
                }
            }

            for await (visitId, people) in group {
                await MainActor.run {
                    self.visitPeopleCache[visitId] = people
                }
            }
        }
    }

    private func loadMonthVisitLabels(for month: Date) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            await MainActor.run {
                monthVisitLabels = [:]
            }
            return
        }

        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select("saved_place_id, entry_time")
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: monthInterval.start.ISO8601Format())
                .lt("entry_time", value: monthInterval.end.ISO8601Format())
                .order("entry_time", ascending: true)
                .execute()

            let visits = try JSONDecoder.supabaseDecoder().decode([MonthVisitLabelData].self, from: response.data)

            var visitsByDay: [Date: [UUID]] = [:]
            for visit in visits {
                let day = calendar.startOfDay(for: visit.entryTime)
                visitsByDay[day, default: []].append(visit.savedPlaceId)
            }

            var computedLabels: [Date: String] = [:]
            for (day, placeIds) in visitsByDay {
                var uniquePlaceIds: [UUID] = []
                for placeId in placeIds where !uniquePlaceIds.contains(placeId) {
                    uniquePlaceIds.append(placeId)
                }

                guard let firstPlaceId = uniquePlaceIds.first else { continue }
                let firstPlaceName = locationsManager.savedPlaces.first(where: { $0.id == firstPlaceId })?.displayName ?? "Visit"

                if uniquePlaceIds.count > 1 {
                    computedLabels[day] = "\(firstPlaceName) +\(uniquePlaceIds.count - 1)"
                } else {
                    computedLabels[day] = firstPlaceName
                }
            }

            await MainActor.run {
                monthVisitLabels = computedLabels
            }
        } catch {
            print("❌ Failed to load month visit labels: \(error)")
        }
    }

    private func refreshLinkedReceiptLinks() {
        linkedReceiptIds = VisitReceiptLinkStore.allLinks()
    }

    private func linkedReceipt(for visit: LocationVisitRecord) -> Note? {
        guard let linkedNoteId = linkedReceiptIds[visit.id] else { return nil }
        return notesManager.notes.first(where: { $0.id == linkedNoteId })
    }
    
    private func colorForRelationship(_ relationship: RelationshipType) -> Color {
        switch relationship {
        case .family: return Color(red: 0.8, green: 0.3, blue: 0.3)
        case .partner: return Color(red: 0.9, green: 0.3, blue: 0.5)
        case .closeFriend: return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .friend: return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .coworker: return Color(red: 0.5, green: 0.5, blue: 0.7)
        case .classmate: return Color(red: 0.6, green: 0.4, blue: 0.7)
        case .neighbor: return Color(red: 0.5, green: 0.6, blue: 0.5)
        case .mentor: return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .acquaintance: return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .other: return Color(red: 0.4, green: 0.4, blue: 0.4)
        }
    }
    
}

#Preview {
    LocationTimelineView(colorScheme: .light)
}
