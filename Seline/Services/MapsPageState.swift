import Combine
import Foundation

@MainActor
final class MapsPageState: ObservableObject {
    typealias FolderBreakdownRow = (name: String, places: [SavedPlace], favourites: Int)
    typealias PlaceVisitCount = (place: SavedPlace, count: Int)
    typealias NamedCount = (name: String, count: Int)

    private struct Inputs: Equatable {
        let searchText: String
        let hubPeriodVisits: [LocationVisitRecord]
        let hubRangeStart: Date
    }

    @Published private(set) var filteredSavedPlaces: [SavedPlace] = []
    @Published private(set) var filteredFavouritePlaces: [SavedPlace] = []
    @Published private(set) var savedFolderBreakdownRows: [FolderBreakdownRow] = []
    @Published private(set) var hubVisitedPlacesByCount: [PlaceVisitCount] = []
    @Published private(set) var hubPlaceCategoryBreakdown: [NamedCount] = []
    @Published private(set) var hubPeopleRelationshipBreakdown: [NamedCount] = []
    @Published private(set) var hubRecentPeople: [Person] = []
    @Published private(set) var peopleCount: Int = 0
    @Published private(set) var favouritePeopleCount: Int = 0
    @Published private(set) var peopleAddedThisMonthCount: Int = 0
    @Published private(set) var hubPeopleUpdatedInRangeCount: Int = 0

    private let locationsManager: LocationsManager
    private let peopleManager: PeopleManager
    private var cancellables = Set<AnyCancellable>()
    private var refreshGeneration = 0

    private var savedPlaces: [SavedPlace] = []
    private var categories: [String] = []
    private var userFolders: Set<String> = []
    private var people: [Person] = []
    private var searchText: String = ""
    private var hubPeriodVisits: [LocationVisitRecord] = []
    private var hubDateRange = DateInterval(start: .distantPast, end: Date())
    private var currentInputs: Inputs?

    init(
        locationsManager: LocationsManager = .shared,
        peopleManager: PeopleManager = .shared
    ) {
        self.locationsManager = locationsManager
        self.peopleManager = peopleManager

        bind()
        savedPlaces = locationsManager.savedPlaces
        categories = locationsManager.categories
        userFolders = locationsManager.userFolders
        people = peopleManager.people
        currentInputs = Inputs(
            searchText: searchText,
            hubPeriodVisits: hubPeriodVisits,
            hubRangeStart: hubDateRange.start
        )
        refresh()
    }

    func updateInputs(
        searchText: String,
        hubPeriodVisits: [LocationVisitRecord],
        hubDateRange: DateInterval
    ) {
        let nextInputs = Inputs(
            searchText: searchText,
            hubPeriodVisits: hubPeriodVisits,
            hubRangeStart: hubDateRange.start
        )
        guard currentInputs != nextInputs else {
            return
        }

        currentInputs = nextInputs
        self.searchText = searchText
        self.hubPeriodVisits = hubPeriodVisits
        self.hubDateRange = hubDateRange
        refresh()
    }

    func groupedPlaces(for superCategory: LocationSuperCategory) -> [String: [SavedPlace]] {
        var result: [String: [SavedPlace]] = [:]

        for category in categories {
            if locationsManager.getSuperCategory(for: category) == superCategory {
                let categoryPlaces = filteredSavedPlaces.filter { $0.category == category }
                if !categoryPlaces.isEmpty || userFolders.contains(category) {
                    result[category] = categoryPlaces
                }
            }
        }

        return result
    }

    private func bind() {
        locationsManager.$savedPlaces
            .sink { [weak self] places in
                self?.savedPlaces = places
                self?.refresh()
            }
            .store(in: &cancellables)

        locationsManager.$categories
            .sink { [weak self] categories in
                self?.categories = categories
                self?.refresh()
            }
            .store(in: &cancellables)

        locationsManager.$userFolders
            .sink { [weak self] folders in
                self?.userFolders = folders
                self?.refresh()
            }
            .store(in: &cancellables)

        peopleManager.$people
            .sink { [weak self] people in
                self?.people = people
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        let savedPlaces = self.savedPlaces
        let userFolders = self.userFolders
        let people = self.people
        let searchText = self.searchText
        let hubPeriodVisits = self.hubPeriodVisits
        let hubDateRange = self.hubDateRange

        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            func matchesQuery(_ place: SavedPlace) -> Bool {
                place.matchesSearchQuery(searchText)
            }

            let nextFilteredSavedPlaces = savedPlaces.filter(matchesQuery)
            let nextFilteredFavouritePlaces = savedPlaces
                .filter(\.isFavourite)
                .filter(matchesQuery)

            let groupedFolders = Dictionary(grouping: nextFilteredSavedPlaces, by: \.category)
            let folderNames = Set(groupedFolders.keys).union(userFolders)
            let nextSavedFolderBreakdownRows: [FolderBreakdownRow] = folderNames
                .map { folderName in
                    let places = (groupedFolders[folderName] ?? []).sorted { lhs, rhs in
                        if lhs.isFavourite != rhs.isFavourite {
                            return lhs.isFavourite && !rhs.isFavourite
                        }
                        return lhs.displayName < rhs.displayName
                    }

                    return (
                        name: folderName,
                        places: places,
                        favourites: places.filter(\.isFavourite).count
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.places.count == rhs.places.count {
                        return lhs.name < rhs.name
                    }
                    return lhs.places.count > rhs.places.count
                }

            let savedPlacesById = Dictionary(uniqueKeysWithValues: savedPlaces.map { ($0.id, $0) })
            var visitCounts: [UUID: Int] = [:]
            for visit in hubPeriodVisits {
                visitCounts[visit.savedPlaceId, default: 0] += 1
            }

            let nextHubVisitedPlacesByCount: [PlaceVisitCount] = visitCounts
                .compactMap { entry in
                    savedPlacesById[entry.key].map { (place: $0, count: entry.value) }
                }
                .sorted { lhs, rhs in
                    if lhs.count == rhs.count {
                        return lhs.place.displayName < rhs.place.displayName
                    }
                    return lhs.count > rhs.count
                }

            let nextHubPlaceCategoryBreakdown: [NamedCount] = {
                var counts: [String: Int] = [:]

                for visit in hubPeriodVisits {
                    if let place = savedPlacesById[visit.savedPlaceId] {
                        counts[place.category, default: 0] += 1
                    }
                }

                if counts.isEmpty {
                    for place in nextFilteredSavedPlaces {
                        counts[place.category, default: 0] += 1
                    }
                }

                return counts
                    .map { (name: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count == rhs.count {
                            return lhs.name < rhs.name
                        }
                        return lhs.count > rhs.count
                    }
            }()

            let nextHubPeopleRelationshipBreakdown: [NamedCount] = Dictionary(
                grouping: people,
                by: \.relationshipDisplayText
            )
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name < rhs.name
                }
                return lhs.count > rhs.count
            }

            let nextHubRecentPeople = people.sorted { $0.dateModified > $1.dateModified }
            let nextPeopleCount = people.count
            let nextFavouritePeopleCount = people.filter(\.isFavourite).count

            let calendar = Calendar.current
            let now = Date()
            let nextPeopleAddedThisMonthCount = people.filter {
                calendar.isDate($0.dateModified, equalTo: now, toGranularity: .month)
            }.count
            let nextHubPeopleUpdatedInRangeCount = people.filter {
                $0.dateModified >= hubDateRange.start && $0.dateModified <= hubDateRange.end
            }.count

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation else { return }

                self.filteredSavedPlaces = nextFilteredSavedPlaces
                self.filteredFavouritePlaces = nextFilteredFavouritePlaces
                self.savedFolderBreakdownRows = nextSavedFolderBreakdownRows
                self.hubVisitedPlacesByCount = nextHubVisitedPlacesByCount
                self.hubPlaceCategoryBreakdown = nextHubPlaceCategoryBreakdown
                self.hubPeopleRelationshipBreakdown = nextHubPeopleRelationshipBreakdown
                self.hubRecentPeople = nextHubRecentPeople
                self.peopleCount = nextPeopleCount
                self.favouritePeopleCount = nextFavouritePeopleCount
                self.peopleAddedThisMonthCount = nextPeopleAddedThisMonthCount
                self.hubPeopleUpdatedInRangeCount = nextHubPeopleUpdatedInRangeCount
            }
        }
    }
}
