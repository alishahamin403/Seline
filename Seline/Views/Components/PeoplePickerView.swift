import SwiftUI

/// A reusable component for selecting people to associate with visits, receipts, etc.
struct PeoplePickerView: View {
    @ObservedObject var peopleManager: PeopleManager
    @Binding var selectedPeopleIds: Set<UUID>
    let colorScheme: ColorScheme
    var title: String = "Who was with you?"
    var showHeader: Bool = true
    var maxHeight: CGFloat? = 300  // nil = unlimited, defaults to 300 for backward compatibility

    @State private var searchText: String = ""

    private var filteredPeople: [Person] {
        let sorted = peopleManager.people.sorted { $0.name < $1.name }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { person in
            person.name.localizedCaseInsensitiveContains(searchText) ||
            person.relationship.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(FontManager.geist(size: 14, weight: .medium))
                    Text(title)
                        .font(FontManager.geist(size: 16, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
            }

            if peopleManager.people.isEmpty {
                Text("No people saved yet. Add people from the Maps > People tab.")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                    TextField("Search people...", text: $searchText)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                )

                // Vertical scrollable list of people
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(filteredPeople) { person in
                            personRow(person: person)
                        }

                        if filteredPeople.isEmpty {
                            Text("No people match your search")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: maxHeight)

                // Show selected people count
                if !selectedPeopleIds.isEmpty {
                    Text("\(selectedPeopleIds.count) \(selectedPeopleIds.count == 1 ? "person" : "people") selected")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
        }
    }
    
    private func personRow(person: Person) -> some View {
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
            HStack(spacing: 12) {
                // Avatar or initials
                Circle()
                    .fill(colorForRelationship(person.relationship))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(person.initials)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(person.relationship.rawValue.capitalized)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }

                Spacer()

                // Checkmark indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(FontManager.geist(size: 22, weight: .medium))
                        .foregroundColor(colorForRelationship(person.relationship))
                } else {
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ?
                          colorForRelationship(person.relationship).opacity(0.15) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02)))
            )
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
}

/// A compact version that shows selected people as avatars with a button to edit
struct PeoplePickerCompact: View {
    @ObservedObject var peopleManager: PeopleManager
    @Binding var selectedPeopleIds: Set<UUID>
    let colorScheme: ColorScheme
    let onEditTap: () -> Void
    
    var selectedPeople: [Person] {
        selectedPeopleIds.compactMap { id in
            peopleManager.people.first { $0.id == id }
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Show selected people avatars
            if !selectedPeople.isEmpty {
                HStack(spacing: -6) {
                    ForEach(selectedPeople.prefix(4)) { person in
                        Circle()
                            .fill(colorForRelationship(person.relationship))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(person.initials)
                                    .font(FontManager.geist(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                            )
                    }
                    
                    if selectedPeople.count > 4 {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("+\(selectedPeople.count - 4)")
                                    .font(FontManager.geist(size: 10, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            )
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                            )
                    }
                }
                
                Text("with \(selectedPeople.prefix(2).map { $0.displayName }.joined(separator: ", "))\(selectedPeople.count > 2 ? "..." : "")")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            } else {
                Image(systemName: "person.2")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                
                Text("Add people")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            
            Spacer()
            
            // Edit button
            Button(action: onEditTap) {
                Image(systemName: "pencil.circle.fill")
                    .font(FontManager.geist(size: 20, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
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
