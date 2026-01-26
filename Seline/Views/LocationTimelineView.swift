import SwiftUI
import PostgREST

struct LocationTimelineView: View {
    let colorScheme: ColorScheme

    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var peopleManager = PeopleManager.shared

    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var visitsForSelectedDay: [LocationVisitRecord] = []
    @State private var visitsForMonth: [Date: Int] = [:] // Date -> visit count
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
    @State private var daySummaryText: String? = nil
    @State private var isGeneratingSummary = false
    @State private var lastSummaryGeneratedFor: Date? = nil
    @State private var lastSummaryNotesHash: Int = 0 // Hash of visit notes for cache invalidation
    @State private var visitPeopleCache: [UUID: [Person]] = [:] // Cache people for each visit

    private let calendar = Calendar.current

    /// Returns visits for the selected day that have notes/reasons
    private var visitsWithNotes: [LocationVisitRecord] {
        visitsForSelectedDay.filter { visit in
            if let notes = visit.visitNotes, !notes.isEmpty {
                return true
            }
            return false
        }.sorted(by: { $0.entryTime < $1.entryTime })
    }

    /// Hash of current visit notes to detect when content changes
    private var currentNotesHash: Int {
        var hasher = Hasher()
        for visit in visitsWithNotes {
            hasher.combine(visit.id)
            hasher.combine(visit.visitNotes ?? "")
        }
        return hasher.finalize()
    }
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Calendar section
            calendarSection

            // Timeline section for selected day
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if visitsForSelectedDay.isEmpty {
                emptyDayView
            } else {
                timelineSection
            }

            Spacer()
        }
        .onAppear {
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .task {
            // CRITICAL: Run midnight fix on first load to ensure data consistency
            // This ensures calendar and history views show matching data
            let result = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
            if result.fixed > 0 {
                print("✅ Fixed \(result.fixed) midnight-spanning visits on timeline load")
                // Invalidate all caches and reload
                await MainActor.run {
                    LocationVisitAnalytics.shared.invalidateAllVisitCaches()
                }
                loadVisitsForMonth()
                loadVisitsForSelectedDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
            // CRITICAL: Update calendar view in real-time when visit is created
            // This ensures calendar view matches the accuracy of geofence tracking
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VisitHistoryUpdated"))) { _ in
            // CRITICAL: Invalidate cache before reloading to ensure fresh data matches visit history
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let dayKey = dayFormatter.string(from: selectedDate)
            CacheManager.shared.invalidate(forKey: "cache.visits.day.\(dayKey)")
            
            // Refresh when visits are updated (e.g., after midnight split fixes)
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .onChange(of: selectedDate) { _ in
            // Reload visits when selected date changes
            loadVisitsForSelectedDay()
            // Clear summary so it regenerates for the new date
            daySummaryText = nil
        }
        .onChange(of: visitsForSelectedDay.count) { _ in
            // Generate summary after visits are loaded (fixes cache not showing on first load)
            // Only generate if we have visits with notes
            if !visitsWithNotes.isEmpty {
                generateDaySummaryIfNeeded()
            } else {
                daySummaryText = nil
            }
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
    }

    // MARK: - Calendar Section

    @ViewBuilder
    private var calendarSection: some View {
        VStack(spacing: 6) {
            // Month navigation
            HStack(spacing: 8) {
                // Previous month button
                Button(action: {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                        loadVisitsForMonth()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Month and year
                Text(dateFormatter.string(from: currentMonth))
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)

                // Today button
                Button(action: {
                    withAnimation {
                        let today = Date()
                        currentMonth = today
                        selectedDate = today
                        loadVisitsForMonth()
                        loadVisitsForSelectedDay()
                    }
                }) {
                    Text("Today")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Next month button
                Button(action: {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                        loadVisitsForMonth()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Day headers
            HStack(spacing: 0) {
                ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                    Text(day)
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        calendarDayCell(for: date)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .shadcnTileStyle(colorScheme: colorScheme)
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func calendarDayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let visitCount = visitsForMonth[normalizeDate(date)] ?? 0
        let hasVisits = visitCount > 0
        let isInCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)

        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedDate = date
                loadVisitsForSelectedDay()
            }
        }) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(FontManager.geist(size: 13, systemWeight: isToday ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? Color.black : Color.white) :
                        isToday ? (colorScheme == .dark ? Color.white : Color.black) :
                        !isInCurrentMonth ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.4) :
                        (colorScheme == .dark ? Color.white : Color.black)
                    )

                // Visit indicator - show up to 3 dots
                if hasVisits {
                    HStack(spacing: 2) {
                        ForEach(0..<min(visitCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    // Empty space to maintain consistent height
                    HStack(spacing: 2) {}
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                isSelected ? (colorScheme == .dark ? Color.white : Color.black) :
                isToday ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.1) :
                Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Timeline Section

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day summary - cleaner header
            HStack(spacing: 0) {
                // Merge button (left side)
                if visitsForSelectedDay.count >= 2 {
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
                        .foregroundColor(isMergeMode ? .red : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isMergeMode ? Color.red.opacity(0.15) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                // Visit count (center-left)
                Text("\(visitsForSelectedDay.count) visit\(visitsForSelectedDay.count == 1 ? "" : "s")")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                Spacer()

                // Total time (right side)
                Text(totalTimeString())
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
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

            // Day summary section (only shows when there are visits with notes)
            if !visitsWithNotes.isEmpty {
                daySummarySection
            }

            // Vertical timeline - cleaner spacing
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime })) { visit in
                        visitCard(for: visit)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .shadcnTileStyle(colorScheme: colorScheme)
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.vertical, 12)
        .alert("Merge Failed", isPresented: $showMergeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mergeErrorMessage)
        }
    }

    @ViewBuilder
    private func visitCard(for visit: LocationVisitRecord) -> some View {
        if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
            let isSelectedForMerge = selectedVisitsForMerge.contains(visit.id)
            let selectionIndex = selectedVisitsForMerge.firstIndex(of: visit.id)
            
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
                            
                            // Show people who were present at this visit (tappable to edit)
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
                                } else {
                                    // Show "Add people" button if no people connected
                                    Button(action: {
                                        selectedVisitForPeople = visit
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.badge.plus")
                                                .font(FontManager.geist(size: 10, weight: .medium))
                                            Text("Add people")
                                                .font(FontManager.geist(size: 10, weight: .medium))
                                        }
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.top, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isMergeMode {
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
                            // Show note icon if visit has notes, calendar+ icon if no notes
                            if let notes = visit.visitNotes, !notes.isEmpty {
                                // Has notes - show note icon to view
                                Button(action: {
                                    selectedVisitForNotes = visit
                                }) {
                                    Image(systemName: "note.text")
                                        .font(FontManager.geist(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.blue.opacity(0.8) : Color.blue)
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

    // MARK: - Day Summary Section

    @ViewBuilder
    private var daySummarySection: some View {
        daySummaryContent
            .background(daySummaryBackground)
            .overlay(daySummaryBorder)
            .padding(.horizontal, 20)
            .onAppear {
                // Generate summary when section appears
                generateDaySummaryIfNeeded()
            }
            .onChange(of: visitsForSelectedDay.count) { _ in
                // Regenerate when visits count changes
                generateDaySummaryIfNeeded()
            }
            .onChange(of: currentNotesHash) { _ in
                // Regenerate when visit notes change (after visits are loaded)
                generateDaySummaryIfNeeded()
            }
    }

    @ViewBuilder
    private var daySummaryContent: some View {
        Group {
            if isGeneratingSummary {
                daySummaryLoadingView
            } else if let summary = daySummaryText {
                daySummaryTextView(summary)
            }
        }
    }

    private var daySummaryLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Summarizing...")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func daySummaryTextView(_ summary: String) -> some View {
        Text(summary)
            .font(FontManager.geist(size: 13, weight: .regular))
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    private var daySummaryBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
    }

    private var daySummaryBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
    }

    private func generateDaySummaryIfNeeded() {
        // Only generate if we have visits with notes
        guard !visitsWithNotes.isEmpty else {
            daySummaryText = nil
            return
        }

        // Calculate hash of visits WITH NOTES for cache invalidation
        var hasher = Hasher()
        for visit in visitsWithNotes.sorted(by: { $0.entryTime < $1.entryTime }) {
            hasher.combine(visit.id)
            hasher.combine(visit.visitNotes ?? "")
        }
        let combinedHash = Int(hasher.finalize())

        // Also check in-memory state (for same session)
        let normalizedDate = normalizeDate(selectedDate)
        if lastSummaryGeneratedFor == normalizedDate &&
           lastSummaryNotesHash == combinedHash &&
           daySummaryText != nil {
            return
        }

        isGeneratingSummary = true

        Task {
            // First try to load from Supabase
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateKey = dateFormatter.string(from: selectedDate)
            
            if let savedSummary = await loadDaySummaryFromSupabase(for: dateKey) {
                // Check if hash matches (visits haven't changed)
                if savedSummary.visitsHash == combinedHash {
                    await MainActor.run {
                        daySummaryText = savedSummary.summaryText
                        lastSummaryGeneratedFor = normalizedDate
                        lastSummaryNotesHash = combinedHash
                        isGeneratingSummary = false
                    }
                    return
                }
                // Hash mismatch - visits changed, need to regenerate
            }
            
            // Generate new summary or regenerate if visits changed
            let summary = await generateDaySummary()
            await MainActor.run {
                daySummaryText = summary
                lastSummaryGeneratedFor = normalizedDate
                lastSummaryNotesHash = combinedHash
                isGeneratingSummary = false
            }
            
            // Save to Supabase
            if let summary = summary {
                await saveDaySummaryToSupabase(date: dateKey, summary: summary, visitsHash: combinedHash)
            }
        }
    }

    private func generateDaySummary() async -> String? {
        // Only generate summary if we have visits with notes
        guard !visitsWithNotes.isEmpty else {
            return nil
        }

        // Build the context from all visits WITH NOTES for the day
        var visitDetails: [String] = []
        let sortedVisits = visitsWithNotes.sorted(by: { $0.entryTime < $1.entryTime })

        for visit in sortedVisits {
            let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
            let placeName = place?.displayName ?? "Unknown"
            
            // Format visit details with time and notes
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let entryTime = timeFormatter.string(from: visit.entryTime)
            
            if let notes = visit.visitNotes, !notes.isEmpty {
                visitDetails.append("\(placeName) at \(entryTime): \(notes)")
            }
        }

        let visitContext = visitDetails.joined(separator: "\n")

        // Generate concise, factual AI summary with key content from visits only
        let systemPrompt = """
        Create a concise day summary in first person that ONLY includes facts from the visit notes provided.
        DO NOT add any information that is not explicitly mentioned in the visit notes.
        DO NOT make assumptions or add extra details.
        Keep it brief: 1-2 sentences (20-40 words maximum).
        Only mention what the user actually did based on the notes provided.
        Format: Simple, factual statement. Example: "Relaxed at home, then worked out focusing on hamstrings, back, and triceps. Had a massage at V-One Wellness."
        """

        let userPrompt = "Visit notes for today:\n\(visitContext)\n\nCreate a concise summary using ONLY the information above:"

        do {
            let summary = try await OpenAIService.shared.generateText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: 80,
                temperature: 0.3
            )
            return summary
        } catch {
            print("❌ Failed to generate day summary: \(error)")
            // Return a simple fallback that at least includes the places with notes
            return createFallbackSummary()
        }
    }

    private func createFallbackSummary() -> String {
        let sortedVisits = visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime })
        let places = sortedVisits.compactMap { visit -> String? in
            locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })?.displayName
        }

        // Deduplicate consecutive same locations (e.g., Home → Gym → Home becomes "Home, Gym, Home")
        var dedupedPlaces: [String] = []
        for place in places {
            if dedupedPlaces.last != place {
                dedupedPlaces.append(place)
            }
        }

        if dedupedPlaces.count == 1 {
            return "Spent time at \(dedupedPlaces[0])"
        } else if dedupedPlaces.count <= 3 {
            return dedupedPlaces.joined(separator: " → ")
        } else {
            // For more than 3 places, show first few and count
            let shown = dedupedPlaces.prefix(3).joined(separator: " → ")
            let remaining = dedupedPlaces.count - 3
            return "\(shown) + \(remaining) more"
        }
    }

    // MARK: - Helper Functions

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        let daysCount = calendar.component(.weekday, from: monthInterval.start) - 1
        var days: [Date?] = Array(repeating: nil, count: daysCount)

        var date = monthInterval.start
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return days
    }

    private func normalizeDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private func selectedDayString() -> String {
        let formatter = DateFormatter()
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: selectedDate)
        }
    }

    private func visitSummary() -> String {
        let count = visitsForSelectedDay.count
        let totalMinutes = visitsForSelectedDay.compactMap { $0.durationMinutes }.reduce(0, +)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(count) visit\(count == 1 ? "" : "s") • \(hours)h \(minutes)m"
        } else {
            return "\(count) visit\(count == 1 ? "" : "s") • \(minutes)m"
        }
    }

    private func totalTimeString() -> String {
        let totalMinutes = visitsForSelectedDay.compactMap { $0.durationMinutes }.reduce(0, +)
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
            
            // Regenerate day summary since visit notes changed
            await MainActor.run {
                daySummaryText = nil
                lastSummaryGeneratedFor = nil
                lastSummaryNotesHash = 0
            }
            generateDaySummaryIfNeeded()
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
           let firstVisit = visitsForSelectedDay.first(where: { $0.id == firstVisitId }) {
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
        guard let firstVisit = visitsForSelectedDay.first(where: { $0.id == firstVisitId }),
              let secondVisit = visitsForSelectedDay.first(where: { $0.id == secondVisitId }) else {
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
            let dayKey = dayFormatter.string(from: selectedDate)
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
            return Color.orange
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
            guard let userId = supabaseManager.getCurrentUser()?.id else { return }

            // Get first and last day of month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return }

            // OPTIMIZATION: Create cache key for this month
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            let monthKey = monthFormatter.string(from: currentMonth)
            let cacheKey = "cache.visits.month.\(monthKey)"

            // Check cache first
            if let cachedVisits: [Date: Int] = CacheManager.shared.get(forKey: cacheKey) {
                await MainActor.run {
                    visitsForMonth = cachedVisits
                }
                return
            }

            do {
                let client = await supabaseManager.getPostgrestClient()
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .gte("entry_time", value: monthInterval.start.ISO8601Format())
                    .lte("entry_time", value: monthInterval.end.ISO8601Format())
                    .execute()

                let decoder = JSONDecoder.supabaseDecoder()
                let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

                // Group by day
                var visitsByDay: [Date: Int] = [:]
                for visit in visits {
                    let normalizedDate = normalizeDate(visit.entryTime)
                    visitsByDay[normalizedDate, default: 0] += 1
                }

                await MainActor.run {
                    visitsForMonth = visitsByDay
                    // OPTIMIZATION: Cache for 5 minutes
                    CacheManager.shared.set(visitsByDay, forKey: cacheKey, ttl: CacheManager.TTL.medium)
                }
            } catch {
                print("Error loading visits for month: \(error)")
            }
        }
    }

    private func loadVisitsForSelectedDay() {
        Task {
            guard let userId = supabaseManager.getCurrentUser()?.id else { return }

            // OPTIMIZATION: Create cache key for this day
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let dayKey = dayFormatter.string(from: selectedDate)
            let cacheKey = "cache.visits.day.\(dayKey)"
            
            // Check cache first (use shorter TTL for daily data - 2 minutes)
            if let cachedVisits: [LocationVisitRecord] = CacheManager.shared.get(forKey: cacheKey) {
                await MainActor.run {
                    visitsForSelectedDay = cachedVisits
                }
                return
            }

            await MainActor.run {
                isLoading = true
            }

            // Get start and end of selected day
            let startOfDay = calendar.startOfDay(for: selectedDate)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

            do {
                let client = await supabaseManager.getPostgrestClient()
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .gte("entry_time", value: startOfDay.ISO8601Format())
                    .lt("entry_time", value: endOfDay.ISO8601Format())
                    .execute()

                let decoder = JSONDecoder.supabaseDecoder()
                let rawVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
                
                // CRITICAL: Process visits using shared function to ensure consistency with visit history view
                // This splits midnight-spanning visits and merges gaps
                let processedVisits = LocationVisitAnalytics.shared.processVisitsForDisplay(rawVisits)

                await MainActor.run {
                    visitsForSelectedDay = processedVisits
                    isLoading = false
                    // OPTIMIZATION: Cache for 2 minutes (shorter TTL for daily data that updates more often)
                    CacheManager.shared.set(processedVisits, forKey: cacheKey, ttl: 120) // 2 minutes
                }
                
                // Load people for each visit
                await loadPeopleForVisits(processedVisits)
            } catch {
                print("Error loading visits for day: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Load People for Visits
    
    private func loadPeopleForVisits(_ visits: [LocationVisitRecord]) async {
        for visit in visits {
            let people = await peopleManager.getPeopleForVisit(visitId: visit.id)
            await MainActor.run {
                visitPeopleCache[visit.id] = people
            }
        }
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
    
    // MARK: - Day Summary Supabase Functions
    
    private func loadDaySummaryFromSupabase(for dateKey: String) async -> (summaryText: String, visitsHash: Int)? {
        guard let userId = supabaseManager.getCurrentUser()?.id else { return nil }
        
        do {
            let client = await supabaseManager.getPostgrestClient()
            let response = try await client
                .from("day_summaries")
                .select("summary_text, visits_hash")
                .eq("user_id", value: userId.uuidString)
                .eq("summary_date", value: dateKey)
                .execute()
            
            let decoder = JSONDecoder()
            struct DaySummaryResponse: Codable {
                let summary_text: String
                let visits_hash: Int
            }
            
            let summaries: [DaySummaryResponse] = try decoder.decode([DaySummaryResponse].self, from: response.data)
            
            if let summary = summaries.first {
                return (summary.summary_text, summary.visits_hash)
            }
            
            return nil
        } catch {
            print("❌ Failed to load day summary from Supabase: \(error)")
            return nil
        }
    }
    
    private func saveDaySummaryToSupabase(date dateKey: String, summary: String, visitsHash: Int) async {
        guard let userId = supabaseManager.getCurrentUser()?.id else { return }
        
        do {
            let client = await supabaseManager.getPostgrestClient()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = formatter.string(from: Date())
            
            // Use upsert to insert or update
            // Note: visits_hash is stored as BIGINT in database, use string representation to avoid precision issues
            let summaryData: [String: PostgREST.AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "summary_date": .string(dateKey),
                "summary_text": .string(summary),
                "visits_hash": .string(String(visitsHash)), // Store as string to preserve full 64-bit value
                "updated_at": .string(nowString)
            ]
            
            try await client
                .from("day_summaries")
                .upsert(summaryData, onConflict: "user_id,summary_date")
                .execute()
            
            print("✅ Saved day summary to Supabase for date: \(dateKey)")
        } catch {
            print("❌ Failed to save day summary to Supabase: \(error)")
        }
    }
}

#Preview {
    LocationTimelineView(colorScheme: .light)
}
