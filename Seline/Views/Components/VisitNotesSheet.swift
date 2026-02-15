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
            if isLoadingPeople {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .padding(.top, 8)
            } else {
                // Use the improved PeoplePickerView component with search and vertical list
                PeoplePickerView(
                    peopleManager: peopleManager,
                    selectedPeopleIds: $selectedPeopleIds,
                    colorScheme: colorScheme,
                    title: "Who was with you?",
                    showHeader: true
                )
            }
        }
        .padding(.top, 8)
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
