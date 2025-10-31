import SwiftUI

// MARK: - Search Models

struct SearchableItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let content: String
    let type: TabSelection
    let identifier: String
    let metadata: [String: String]
    let tags: [String]  // Topics/categories for better connections
    let relatedItems: [String]  // IDs of related items (notes mentioning each other, etc.)

    init(title: String, content: String, type: TabSelection, identifier: String, metadata: [String: String] = [:], tags: [String] = [], relatedItems: [String] = []) {
        self.title = title
        self.content = content
        self.type = type
        self.identifier = identifier
        self.metadata = metadata
        self.tags = tags
        self.relatedItems = relatedItems
    }

    var searchText: String {
        let tagText = tags.joined(separator: " ")
        return "\(title) \(content) \(metadata.values.joined(separator: " ")) \(tagText)"
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