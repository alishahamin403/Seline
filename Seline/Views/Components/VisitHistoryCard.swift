import SwiftUI

// MARK: - Data Model for Grouped Visits

struct VisitDay: Identifiable {
    let id = UUID()
    let date: Date
    let visits: [VisitHistoryItem]

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

struct VisitHistoryCard: View {
    let place: SavedPlace
    @Environment(\.colorScheme) var colorScheme

    @State private var visitHistory: [VisitHistoryItem] = []
    @State private var visitDays: [VisitDay] = []
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var expandedDayIds: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            // Header Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.light()
            }) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Visit History")
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if visitHistory.isEmpty {
                        Text("No visits")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
                .contentShape(Rectangle()) // Ensures the whole area is tappable
            }
            .buttonStyle(PlainButtonStyle())

            // Visit Days List - Day by Day Breakdown
            if isExpanded && !visitHistory.isEmpty {
                VStack(spacing: 10) {
                    ForEach(visitDays) { visitDay in
                        DayVisitGroup(
                            placeId: place.id,
                            visitDay: visitDay,
                            colorScheme: colorScheme,
                            isExpanded: expandedDayIds.contains(visitDay.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedDayIds.contains(visitDay.id) {
                                        expandedDayIds.remove(visitDay.id)
                                    } else {
                                        expandedDayIds.insert(visitDay.id)
                                    }
                                }
                            },
                            onVisitDelete: {
                                // Reload visit history after deletion
                                loadVisitHistory()
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            loadVisitHistory()
        }
    }

    private func loadVisitHistory() {
        isLoading = true
        Task {
            // Fetch with a high limit to get all visits (10000 should be enough for most cases)
            visitHistory = await LocationVisitAnalytics.shared.fetchVisitHistory(for: place.id, limit: 10000)
            // Group visits by date
            groupVisitsByDate()
            isLoading = false
        }
    }

    private func groupVisitsByDate() {
        let calendar = Calendar.current
        var grouped: [Date: [VisitHistoryItem]] = [:]

        // Group visits by calendar day
        for item in visitHistory {
            let components = calendar.dateComponents([.year, .month, .day], from: item.visit.entryTime)
            if let dateKey = calendar.date(from: components) {
                if grouped[dateKey] == nil {
                    grouped[dateKey] = []
                }
                grouped[dateKey]?.append(item)
            }
        }

        // Convert to sorted array (most recent first)
        visitDays = grouped
            .map { date, items in
                VisitDay(date: date, visits: items.sorted { $0.visit.entryTime > $1.visit.entryTime })
            }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Visit History Row

struct VisitHistoryRow: View {
    let visit: LocationVisitRecord
    let colorScheme: ColorScheme
    let onDelete: () -> Void

    @StateObject private var peopleManager = PeopleManager.shared
    @State private var showDeleteConfirmation = false
    @State private var connectedPeople: [Person] = []
    @State private var showPeoplePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date and Duration
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.entryTime.formatted(date: .abbreviated, time: .shortened))
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    HStack(spacing: 8) {
                        Text(visit.dayOfWeek)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("•")
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

                        Text(visit.timeOfDay)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }

                Spacer()

                if let duration = visit.durationMinutes {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(duration))
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Duration")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Active")
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("In Progress")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }
            }

            // Time Range and Delete Button
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(FontManager.geist(size: 10, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                Text(formatTimeRange(entry: visit.entryTime, exit: visit.exitTime))
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                Spacer()

                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash.fill")
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Connected People Section
            if !connectedPeople.isEmpty || !peopleManager.people.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(FontManager.geist(size: 10, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    
                    if connectedPeople.isEmpty {
                        Button(action: {
                            showPeoplePicker = true
                        }) {
                            Text("Add people")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Show connected people avatars
                        HStack(spacing: -6) {
                            ForEach(connectedPeople.prefix(4)) { person in
                                Circle()
                                    .fill(colorForRelationship(person.relationship))
                                    .frame(width: 20, height: 20)
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
                            
                            if connectedPeople.count > 4 {
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text("+\(connectedPeople.count - 4)")
                                            .font(FontManager.geist(size: 8, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1.5)
                                    )
                            }
                        }
                        
                        Button(action: {
                            showPeoplePicker = true
                        }) {
                            Text("Edit")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.leading, 4)
                    }
                    
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
        .task {
            await loadConnectedPeople()
        }
        .sheet(isPresented: $showPeoplePicker) {
            VisitPeoplePickerSheet(
                visit: visit,
                colorScheme: colorScheme,
                onSave: { personIds in
                    Task {
                        await peopleManager.linkPeopleToVisit(
                            visitId: visit.id,
                            personIds: personIds
                        )
                        await loadConnectedPeople()
                    }
                },
                onDismiss: {
                    showPeoplePicker = false
                }
            )
        }
        .confirmationDialog("Delete Visit", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    let success = await LocationVisitAnalytics.shared.deleteVisit(id: visit.id.uuidString)
                    if success {
                        onDelete()
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this visit? This action cannot be undone.")
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }

    private func formatTimeRange(entry: Date, exit: Date?) -> String {
        let entryFormatter = DateFormatter()
        entryFormatter.timeStyle = .short

        let entryStr = entryFormatter.string(from: entry)

        if let exit = exit {
            let exitStr = entryFormatter.string(from: exit)
            return "\(entryStr) - \(exitStr)"
        } else {
            return "Started at \(entryStr)"
        }
    }
    
    private func loadConnectedPeople() async {
        let people = await peopleManager.getPeopleForVisit(visitId: visit.id)
        await MainActor.run {
            connectedPeople = people
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
}

// MARK: - Day Visit Group

struct DayVisitGroup: View {
    let placeId: UUID
    let visitDay: VisitDay
    let colorScheme: ColorScheme
    let isExpanded: Bool
    let onToggle: () -> Void
    let onVisitDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day Header
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visitDay.formattedDate)
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text(visitDay.dayOfWeek)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }

                    Spacer()

                    Text("\(visitDay.visits.count) visit\(visitDay.visits.count == 1 ? "" : "s")")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    Image(systemName: "chevron.right")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Visits for this day - nested/indented inside
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(visitDay.visits, id: \.visit.id) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            VisitHistoryRow(
                                visit: item.visit,
                                colorScheme: colorScheme,
                                onDelete: {
                                    onVisitDelete()
                                }
                            )
                            .padding(.vertical, 10)

                            if item.visit.id != visitDay.visits.last?.visit.id {
                                Divider()
                                    .padding(.horizontal, 0)
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                )
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Visit People Picker Sheet

struct VisitPeoplePickerSheet: View {
    let visit: LocationVisitRecord
    let colorScheme: ColorScheme
    let onSave: ([UUID]) async -> Void
    let onDismiss: () -> Void
    
    @StateObject private var peopleManager = PeopleManager.shared
    @State private var selectedPeopleIds: Set<UUID> = []
    @State private var isLoadingPeople: Bool = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Visit info header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(visit.entryTime.formatted(date: .abbreviated, time: .shortened))
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        if let duration = visit.durationMinutes {
                            Text("Duration: \(formatDuration(duration))")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        }
                    }
                    
                    Divider()
                    
                    // Question
                    Text("Who was with you?")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.top, 8)
                    
                    // People selection
                    if isLoadingPeople {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                        .padding(.top, 8)
                    } else if peopleManager.people.isEmpty {
                        Text("No people added yet. Add people from the People tab.")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .padding(.top, 8)
                    } else {
                        // Horizontal scrollable people chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(peopleManager.people.sorted { $0.name < $1.name }) { person in
                                    personChip(person: person)
                                }
                            }
                        }
                        .padding(.top, 8)
                        
                        // Show selected people count
                        if !selectedPeopleIds.isEmpty {
                            Text("\(selectedPeopleIds.count) \(selectedPeopleIds.count == 1 ? "person" : "people") selected")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                .padding(.top, 4)
                        }
                    }
                    
                    Spacer().frame(height: 40)
                }
                .padding(20)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("Connect People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await onSave(Array(selectedPeopleIds))
                            onDismiss()
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .task {
                // Load existing people connections for this visit
                let existingPeople = await peopleManager.getPeopleForVisit(visitId: visit.id)
                await MainActor.run {
                    selectedPeopleIds = Set(existingPeople.map { $0.id })
                    isLoadingPeople = false
                }
            }
        }
    }
    
    private func personChip(person: Person) -> some View {
        let isSelected = selectedPeopleIds.contains(person.id)
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedPeopleIds.remove(person.id)
                } else {
                    selectedPeopleIds.insert(person.id)
                }
            }
        }) {
            HStack(spacing: 6) {
                // Avatar or initials
                Circle()
                    .fill(colorForRelationship(person.relationship))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(person.initials)
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                Text(person.displayName)
                    .font(FontManager.geist(size: 13, weight: .medium))
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(FontManager.geist(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ?
                          (colorScheme == .dark ? Color.white : Color.black) :
                          (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
            )
            .foregroundColor(isSelected ?
                           (colorScheme == .dark ? Color.black : Color.white) :
                           (colorScheme == .dark ? Color.white : Color.black))
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VisitHistoryCard(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Test Location",
                address: "123 Main St",
                latitude: 37.7749,
                longitude: -122.4194
            )
        )
        .padding()
    }
    .background(Color.black)
}
