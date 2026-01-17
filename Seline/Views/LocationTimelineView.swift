import SwiftUI
import PostgREST

struct LocationTimelineView: View {
    let colorScheme: ColorScheme

    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var locationsManager = LocationsManager.shared

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
    @State private var showingVisitNotesSheet = false
    @State private var selectedVisitForNotes: LocationVisitRecord? = nil
    @State private var daySummaryText: String? = nil
    @State private var isGeneratingSummary = false
    @State private var lastSummaryGeneratedFor: Date? = nil
    @State private var lastSummaryNotesHash: Int = 0 // Hash of visit notes for cache invalidation

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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
            // CRITICAL: Update calendar view in real-time when visit is created
            // This ensures calendar view matches the accuracy of geofence tracking
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .onChange(of: selectedDate) { _ in
            // Reload visits when selected date changes
            loadVisitsForSelectedDay()
            // Clear summary so it regenerates for the new date
            daySummaryText = nil
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place, onDismiss: { 
                selectedPlace = nil
            })
            .presentationBg()
        }
        .sheet(isPresented: $showingVisitNotesSheet) {
            if let visit = selectedVisitForNotes {
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
        .padding(.horizontal, 12)
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
            HStack {
                Text(selectedDayString())
                    .font(FontManager.geist(size: 17, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()

                // Merge button
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

                Text(visitSummary())
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Merge mode instructions
            if isMergeMode {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
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
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                Text("Merge")
                                    .font(FontManager.geist(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green)
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
                        .fill(Color.blue.opacity(0.1))
                )
                .padding(.horizontal, 20)
            }

            // Day summary section (always shows when there are visits)
            if !visitsForSelectedDay.isEmpty {
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
        .padding(.horizontal, 12)
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
                    // Simplified timeline indicator - smaller and cleaner
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(categoryColor(for: place.category))
                                .frame(width: 8, height: 8)
                            
                            // Selection indicator for merge mode
                            if isSelectedForMerge {
                                Circle()
                                    .stroke(Color.green, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                
                                Text("\((selectionIndex ?? 0) + 1)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green)
                                    .offset(x: 10, y: -8)
                            }
                        }

                        if visit.id != visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime }).last?.id {
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                .frame(width: 1.5)
                                .frame(minHeight: 40)
                        }
                    }
                    .frame(width: 20)

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
                        }

                        Spacer()
                        
                        // Merge selection indicator or Notes button
                        if isMergeMode {
                            Image(systemName: isSelectedForMerge ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(isSelectedForMerge ? .green : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                        } else {
                            // Show note icon if visit has notes, calendar+ icon if no notes
                            if let notes = visit.visitNotes, !notes.isEmpty {
                                // Has notes - show note icon to view
                                Button(action: {
                                    selectedVisitForNotes = visit
                                    showingVisitNotesSheet = true
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
                                    showingVisitNotesSheet = true
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
                            .stroke(isSelectedForMerge ? Color.green : Color.clear, lineWidth: 2)
                    )
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
                generateDaySummaryIfNeeded()
            }
            .onChange(of: visitsForSelectedDay.count) { _ in
                // Regenerate when visits count changes
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
        // Only generate if we have visits
        guard !visitsForSelectedDay.isEmpty else {
            daySummaryText = nil
            return
        }

        let normalizedDate = normalizeDate(selectedDate)

        // Use combined hash of visits AND notes for cache invalidation
        var hasher = Hasher()
        for visit in visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime }) {
            hasher.combine(visit.id)
            hasher.combine(visit.visitNotes ?? "")
        }
        let combinedHash = hasher.finalize()

        // Check if we already generated for this date AND the content hasn't changed
        if lastSummaryGeneratedFor == normalizedDate &&
           lastSummaryNotesHash == combinedHash &&
           daySummaryText != nil {
            return
        }

        isGeneratingSummary = true

        Task {
            let summary = await generateDaySummary()
            await MainActor.run {
                daySummaryText = summary
                lastSummaryGeneratedFor = normalizedDate
                lastSummaryNotesHash = combinedHash
                isGeneratingSummary = false
            }
        }
    }

    private func generateDaySummary() async -> String {
        // Build the context from all visits for the day
        var visitDetails: [String] = []
        let sortedVisits = visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime })

        for visit in sortedVisits {
            let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId })
            let placeName = place?.displayName ?? "Unknown"

            // Include notes if available, otherwise just the place name
            if let notes = visit.visitNotes, !notes.isEmpty {
                visitDetails.append("\(placeName): \(notes)")
            } else {
                visitDetails.append(placeName)
            }
        }

        let visitContext = visitDetails.joined(separator: ", ")
        let hasNotes = visitsForSelectedDay.contains { $0.visitNotes != nil && !($0.visitNotes?.isEmpty ?? true) }

        // If we have notes, ask AI to summarize with context
        // If no notes, just list the places visited in order
        if hasNotes {
            let systemPrompt = """
            Create an ultra-concise day summary in first person. Maximum 15-20 words total.
            Cover all activities mentioned. No fluff, just facts. Example: "Home relaxing, gym workout, massage at V-One, then back home."
            """

            let userPrompt = "Summarize: \(visitContext)"

            do {
                let summary = try await OpenAIService.shared.generateText(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: 50,
                    temperature: 0.5
                )
                return summary
            } catch {
                print("❌ Failed to generate day summary: \(error)")
                return createFallbackSummary()
            }
        } else {
            // No notes - just create a simple location list
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

    private func timeRangeString(from visit: LocationVisitRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let entryString = formatter.string(from: visit.entryTime)

        if let exitTime = visit.exitTime {
            let exitString = formatter.string(from: exitTime)
            return "\(entryString) - \(exitString)"
        } else {
            return "\(entryString) - ongoing"
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
                let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

                await MainActor.run {
                    visitsForSelectedDay = visits
                    isLoading = false
                    // OPTIMIZATION: Cache for 2 minutes (shorter TTL for daily data that updates more often)
                    CacheManager.shared.set(visits, forKey: cacheKey, ttl: 120) // 2 minutes
                }
            } catch {
                print("Error loading visits for day: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    LocationTimelineView(colorScheme: .light)
}
