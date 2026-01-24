import SwiftUI

struct VisitNotesSheet: View {
    let visit: LocationVisitRecord
    let place: SavedPlace?
    let colorScheme: ColorScheme
    let onSave: (String) async -> Void
    let onDismiss: () -> Void
    
    @StateObject private var peopleManager = PeopleManager.shared
    @State private var notesText: String
    @State private var selectedPeopleIds: Set<UUID> = []
    @State private var isLoadingPeople: Bool = true
    @FocusState private var isFocused: Bool
    
    init(visit: LocationVisitRecord, place: SavedPlace?, colorScheme: ColorScheme, onSave: @escaping (String) async -> Void, onDismiss: @escaping () -> Void) {
        self.visit = visit
        self.place = place
        self.colorScheme = colorScheme
        self.onSave = onSave
        self.onDismiss = onDismiss
        _notesText = State(initialValue: visit.visitNotes ?? "")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Visit info header
                    VStack(alignment: .leading, spacing: 8) {
                        if let place = place {
                            Text(place.displayName)
                                .font(FontManager.geist(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        
                        HStack(spacing: 8) {
                            Text(timeRangeString)
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            
                            if let duration = visit.durationMinutes {
                                Text("• \(durationString(minutes: duration))")
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Question - combined single question for specific visit
                    Text("Why did you visit and what did you get?")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.top, 8)
                    
                    // Notes input
                    TextField("e.g., bought vitamins and allergy meds for seasonal allergies, picked up groceries for the week...", text: $notesText, axis: .vertical)
                        .font(FontManager.geist(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        )
                        .lineLimit(3...6)
                        .focused($isFocused)
                    
                    // People section
                    if !peopleManager.people.isEmpty {
                        peopleSelectorSection
                    }
                    
                    Spacer().frame(height: 40)
                }
                .padding(20)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("Visit Notes")
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
                            // Save notes
                            await onSave(notesText.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            // Save people connections
                            if !selectedPeopleIds.isEmpty {
                                await peopleManager.linkPeopleToVisit(
                                    visitId: visit.id,
                                    personIds: Array(selectedPeopleIds)
                                )
                            }
                            
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
            .onAppear {
                isFocused = true
            }
        }
    }
    
    // MARK: - People Selector Section
    
    @ViewBuilder
    private var peopleSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(FontManager.geist(size: 14, weight: .medium))
                Text("Who was with you?")
                    .font(FontManager.geist(size: 16, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            if isLoadingPeople {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            } else {
                // Horizontal scrollable people chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(peopleManager.people.sorted { $0.name < $1.name }) { person in
                            personChip(person: person)
                        }
                    }
                }
                
                // Show selected people count
                if !selectedPeopleIds.isEmpty {
                    Text("\(selectedPeopleIds.count) \(selectedPeopleIds.count == 1 ? "person" : "people") selected")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
        }
        .padding(.top, 8)
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
}
