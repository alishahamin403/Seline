import Foundation

@MainActor
final class SelineChatPlacesService {
    private let locationsManager = LocationsManager.shared

    func place(for anchor: SelineChatPlaceAnchor) -> SavedPlace? {
        locationsManager.savedPlaces.first(where: { $0.id == anchor.savedPlaceID })
    }

    func exactMatch(for mention: String) -> SavedPlace? {
        let normalizedMention = normalize(mention)
        guard !normalizedMention.isEmpty else { return nil }

        return locationsManager.savedPlaces.first { place in
            let candidates = placeTextCandidates(for: place)
            return candidates.contains(normalizedMention)
        }
    }

    func rankedMatches(query: String, searchTerms: [String], limit: Int = 6) -> [(place: SavedPlace, score: Double)] {
        let normalizedQuery = normalize(query)
        let normalizedTerms = searchTerms.map(normalize).filter { !$0.isEmpty }

        let scored = locationsManager.savedPlaces.compactMap { place -> (SavedPlace, Double)? in
            let score = score(place: place, normalizedQuery: normalizedQuery, normalizedTerms: normalizedTerms)
            guard score > 0 else { return nil }
            return (place, score)
        }

        return Array(scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.displayName < rhs.0.displayName
            }
            return lhs.1 > rhs.1
        }.prefix(limit))
    }

    func placeResults(from places: [SavedPlace]) -> [SelineChatPlaceResult] {
        places.map { place in
            SelineChatPlaceResult(
                id: place.id.uuidString,
                savedPlaceID: place.id,
                googlePlaceID: place.googlePlaceId,
                name: place.displayName,
                subtitle: place.address,
                latitude: place.latitude,
                longitude: place.longitude,
                category: place.category,
                rating: place.rating,
                isSaved: true
            )
        }
    }

    func makeAnchor(from place: SavedPlace) -> SelineChatPlaceAnchor {
        SelineChatPlaceAnchor(savedPlaceID: place.id, name: place.displayName)
    }

    private func score(place: SavedPlace, normalizedQuery: String, normalizedTerms: [String]) -> Double {
        let haystack = searchableText(for: place)
        guard !haystack.isEmpty else { return 0 }

        var score = 0.0
        if !normalizedQuery.isEmpty {
            if normalize(place.displayName) == normalizedQuery {
                score += 10
            } else if haystack.contains(normalizedQuery) {
                score += 6
            }
        }

        for term in normalizedTerms {
            if term == normalize(place.displayName) {
                score += 4
            } else if haystack.contains(term) {
                score += 1.5
            }
        }

        if place.isFavourite {
            score += 0.25
        }

        return score
    }

    private func searchableText(for place: SavedPlace) -> String {
        [
            Optional(place.displayName),
            Optional(place.name),
            place.address,
            place.city,
            place.province,
            place.category,
            place.userNotes,
            place.userCuisine
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map(normalize)
        .joined(separator: " ")
    }

    private func placeTextCandidates(for place: SavedPlace) -> Set<String> {
        Set(
            [
                Optional(place.displayName),
                Optional(place.name),
                place.address,
                place.customName,
                place.userCuisine
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(normalize)
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
