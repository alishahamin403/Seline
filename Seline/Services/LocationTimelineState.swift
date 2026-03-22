import Combine
import Foundation

@MainActor
final class LocationTimelineState: ObservableObject {
    @Published private(set) var placesById: [UUID: SavedPlace] = [:]
    @Published private(set) var notesById: [UUID: Note] = [:]
    @Published private(set) var sortedSelectedDayVisits: [LocationVisitRecord] = []

    private let locationsManager: LocationsManager
    private let notesManager: NotesManager
    private let visitState: VisitStateManager
    private var cancellables = Set<AnyCancellable>()

    init(
        locationsManager: LocationsManager = .shared,
        notesManager: NotesManager = .shared,
        visitState: VisitStateManager = .shared
    ) {
        self.locationsManager = locationsManager
        self.notesManager = notesManager
        self.visitState = visitState

        bind()
        refreshPlaces(savedPlaces: locationsManager.savedPlaces)
        refreshNotes(notes: notesManager.notes)
        refreshVisits(visits: visitState.selectedDayVisits)
    }

    private func bind() {
        locationsManager.$savedPlaces
            .sink { [weak self] places in
                self?.refreshPlaces(savedPlaces: places)
            }
            .store(in: &cancellables)

        notesManager.$notes
            .sink { [weak self] notes in
                self?.refreshNotes(notes: notes)
            }
            .store(in: &cancellables)

        visitState.$selectedDayVisits
            .sink { [weak self] visits in
                self?.refreshVisits(visits: visits)
            }
            .store(in: &cancellables)
    }

    private func refreshPlaces(savedPlaces: [SavedPlace]) {
        let dictionary = Dictionary(uniqueKeysWithValues: savedPlaces.map { ($0.id, $0) })
        if dictionary != placesById {
            placesById = dictionary
        }
    }

    private func refreshNotes(notes: [Note]) {
        let dictionary = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        if dictionary != notesById {
            notesById = dictionary
        }
    }

    private func refreshVisits(visits: [LocationVisitRecord]) {
        let sortedVisits = visits.sorted { $0.entryTime < $1.entryTime }
        if sortedVisits != sortedSelectedDayVisits {
            sortedSelectedDayVisits = sortedVisits
        }
    }
}
