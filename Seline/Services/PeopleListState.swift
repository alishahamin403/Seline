import Combine
import Foundation

@MainActor
final class PeopleListState: ObservableObject {
    struct Inputs: Equatable {
        let searchText: String
        let selectedRelationshipFilter: String?
    }

    @Published private(set) var filteredPeople: [Person] = []
    @Published private(set) var groupedPeople: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []
    @Published private(set) var favouritePeople: [Person] = []
    @Published private(set) var upcomingBirthdayPeople: [(person: Person, daysUntil: Int)] = []

    private let peopleManager: PeopleManager
    private var cancellables = Set<AnyCancellable>()
    private var inputs = Inputs(searchText: "", selectedRelationshipFilter: nil)
    private var refreshGeneration = 0

    init(peopleManager: PeopleManager = .shared) {
        self.peopleManager = peopleManager

        peopleManager.$people
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    func updateInputs(searchText: String, selectedRelationshipFilter: String?) {
        let nextInputs = Inputs(
            searchText: searchText,
            selectedRelationshipFilter: selectedRelationshipFilter
        )

        guard nextInputs != inputs else { return }
        inputs = nextInputs
        refresh()
    }

    func refresh() {
        let people = peopleManager.people
        let currentInputs = inputs

        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let normalizedQuery = currentInputs.searchText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            var filtered = people

            if !normalizedQuery.isEmpty {
                filtered = filtered.filter { person in
                    person.name.lowercased().contains(normalizedQuery)
                        || (person.nickname?.lowercased().contains(normalizedQuery) ?? false)
                        || person.relationshipDisplayText.lowercased().contains(normalizedQuery)
                        || (person.notes?.lowercased().contains(normalizedQuery) ?? false)
                        || (person.favouriteFood?.lowercased().contains(normalizedQuery) ?? false)
                        || (person.favouriteGift?.lowercased().contains(normalizedQuery) ?? false)
                }
            }

            if let filter = currentInputs.selectedRelationshipFilter {
                filtered = filtered.filter { person in
                    if filter.hasPrefix("custom_") {
                        let customName = String(filter.dropFirst("custom_".count))
                        return person.relationship == .other && person.customRelationship == customName
                    }
                    if filter.hasPrefix("type_") {
                        let typeRawValue = String(filter.dropFirst("type_".count))
                        return person.relationship.rawValue == typeRawValue
                    }
                    return false
                }
            }

            let groupedDict = Dictionary(grouping: filtered) { person -> String in
                if person.relationship == .other,
                   let custom = person.customRelationship,
                   !custom.isEmpty {
                    return "custom_\(custom)"
                }
                return "type_\(person.relationship.rawValue)"
            }

            var grouped: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []

            for relationship in RelationshipType.allCases where relationship != .other {
                let key = "type_\(relationship.rawValue)"
                if let groupPeople = groupedDict[key], !groupPeople.isEmpty {
                    grouped.append((
                        groupKey: key,
                        displayName: relationship.displayName,
                        relationshipType: relationship,
                        people: groupPeople.sorted { $0.name < $1.name }
                    ))
                }
            }

            let customGroups = groupedDict
                .filter { $0.key.hasPrefix("custom_") }
                .sorted { $0.key < $1.key }
                .map { key, groupPeople in
                    (
                        groupKey: key,
                        displayName: String(key.dropFirst("custom_".count)),
                        relationshipType: Optional<RelationshipType>.none,
                        people: groupPeople.sorted { $0.name < $1.name }
                    )
                }
            grouped.append(contentsOf: customGroups)

            let otherKey = "type_\(RelationshipType.other.rawValue)"
            if let otherPeople = groupedDict[otherKey], !otherPeople.isEmpty {
                grouped.append((
                    groupKey: otherKey,
                    displayName: RelationshipType.other.displayName,
                    relationshipType: .other,
                    people: otherPeople.sorted { $0.name < $1.name }
                ))
            }

            let favourites = people
                .filter(\.isFavourite)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let upcomingBirthdays = people
                .compactMap { person -> (person: Person, daysUntil: Int)? in
                    guard let daysUntil = Self.daysUntilBirthday(person), daysUntil <= 30 else { return nil }
                    return (person, daysUntil)
                }
                .sorted {
                    if $0.daysUntil == $1.daysUntil {
                        return $0.person.displayName.localizedCaseInsensitiveCompare($1.person.displayName) == .orderedAscending
                    }
                    return $0.daysUntil < $1.daysUntil
                }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation, self.inputs == currentInputs else { return }

                self.filteredPeople = filtered
                self.groupedPeople = grouped
                self.favouritePeople = favourites
                self.upcomingBirthdayPeople = upcomingBirthdays
            }
        }
    }

    private static func daysUntilBirthday(_ person: Person, from referenceDate: Date = Date()) -> Int? {
        guard let birthday = person.birthday else { return nil }

        let calendar = Calendar.current
        let monthDay = calendar.dateComponents([.month, .day], from: birthday)
        guard let nextBirthday = calendar.nextDate(
            after: calendar.startOfDay(for: referenceDate).addingTimeInterval(-1),
            matching: monthDay,
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            return nil
        }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        let startOfBirthday = calendar.startOfDay(for: nextBirthday)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfBirthday).day
    }
}
