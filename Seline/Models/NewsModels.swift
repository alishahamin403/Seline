import Foundation

enum NewsCategory: String, CaseIterable, Codable {
    case general = "general"
    case technology = "technology"
    case science = "science"
    case business = "business"
    case health = "health"
    case sports = "sports"
    case entertainment = "entertainment"

    var displayName: String {
        switch self {
        case .general: return "Top Stories"
        case .technology: return "Tech"
        case .science: return "Science"
        case .business: return "Business"
        case .health: return "Health"
        case .sports: return "Sports"
        case .entertainment: return "Entertainment"
        }
    }
}

struct NewsArticle: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String?
    let country: String
    let publishedAt: Date
    let url: String
    let source: String

    init(id: UUID = UUID(), title: String, description: String?, country: String, publishedAt: Date, url: String, source: String) {
        self.id = id
        self.title = title
        self.description = description
        self.country = country
        self.publishedAt = publishedAt
        self.url = url
        self.source = source
    }
}

// NewsAPI.org response structures
struct NewsAPIResponse: Codable {
    let status: String
    let totalResults: Int
    let articles: [NewsAPIArticle]
}

struct NewsAPIArticle: Codable {
    let source: NewsAPISource
    let author: String?
    let title: String
    let description: String?
    let url: String
    let publishedAt: String
    let content: String?
}

struct NewsAPISource: Codable {
    let id: String?
    let name: String
}
