import SwiftUI

// MARK: - Search Models

struct SearchableItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let content: String
    let type: TabSelection
    let identifier: String
    let metadata: [String: String]

    init(title: String, content: String, type: TabSelection, identifier: String, metadata: [String: String] = [:]) {
        self.title = title
        self.content = content
        self.type = type
        self.identifier = identifier
        self.metadata = metadata
    }

    var searchText: String {
        return "\(title) \(content) \(metadata.values.joined(separator: " "))"
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let item: SearchableItem
    let relevanceScore: Double
    let matchedText: String

    init(item: SearchableItem, relevanceScore: Double = 1.0, matchedText: String = "") {
        self.item = item
        self.relevanceScore = relevanceScore
        self.matchedText = matchedText.isEmpty ? item.title : matchedText
    }
}

// MARK: - Searchable Protocol

protocol Searchable {
    func getSearchableContent() -> [SearchableItem]
}