import Foundation

class NewsService: ObservableObject {
    static let shared = NewsService()

    @Published var topNews: [NewsArticle] = []
    @Published var isLoading: Bool = false

    // You'll need to get your own API key from https://newsapi.org/
    private let apiKey = "5f3f2612b55c41bab3bb31360c6c2581"
    private let baseURL = "https://newsapi.org/v2/top-headlines"

    // Country code mapping for display
    private let countryNames: [String: String] = [
        "us": "United States",
        "gb": "United Kingdom",
        "ca": "Canada",
        "au": "Australia",
        "de": "Germany",
        "fr": "France",
        "it": "Italy",
        "es": "Spain",
        "jp": "Japan",
        "cn": "China",
        "in": "India",
        "br": "Brazil",
        "mx": "Mexico",
        "ru": "Russia",
        "kr": "South Korea"
    ]

    private init() {
        // Load cached news on init
        loadCachedNews()

        // Start hourly refresh timer
        startHourlyRefresh()
    }

    func fetchTopWorldNews() async {
        // Check if we fetched within the last hour
        if let lastFetchDate = UserDefaults.standard.object(forKey: "lastNewsFetchDate") as? Date {
            let hoursSinceLastFetch = Date().timeIntervalSince(lastFetchDate) / 3600
            if hoursSinceLastFetch < 1.0 && !topNews.isEmpty {
                return // Already fetched within the last hour
            }
        }

        await MainActor.run {
            isLoading = true
        }

        // Fetch top 10 news from US to ensure we get 5 good ones
        if let articles = await fetchNewsForCountry("us", limit: 10) {
            // Filter out articles without images or descriptions, then take top 5
            let validArticles = articles.filter { article in
                article.description != nil && !article.description!.isEmpty
            }
            let sortedArticles = validArticles.sorted { $0.publishedAt > $1.publishedAt }.prefix(5)

            await MainActor.run {
                self.topNews = Array(sortedArticles)
                self.isLoading = false

                // Cache the results
                cacheNews(Array(sortedArticles))
                UserDefaults.standard.set(Date(), forKey: "lastNewsFetchDate")
            }
        } else {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func startHourlyRefresh() {
        // Refresh every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchTopWorldNews()
            }
        }
    }

    private func fetchNewsForCountry(_ countryCode: String, limit: Int = 5) async -> [NewsArticle]? {
        guard let url = URL(string: "\(baseURL)?country=\(countryCode)&pageSize=\(limit)&apiKey=\(apiKey)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NewsAPIResponse.self, from: data)

            let dateFormatter = ISO8601DateFormatter()

            return response.articles.compactMap { article in
                guard let publishedDate = dateFormatter.date(from: article.publishedAt) else {
                    return nil
                }

                let countryName = countryNames[countryCode] ?? countryCode.uppercased()

                return NewsArticle(
                    title: article.title,
                    description: article.description,
                    country: countryName,
                    publishedAt: publishedDate,
                    url: article.url,
                    source: article.source.name
                )
            }
        } catch {
            print("Failed to fetch news for \(countryCode): \(error)")
            return nil
        }
    }

    private func cacheNews(_ articles: [NewsArticle]) {
        if let encoded = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(encoded, forKey: "cachedTopNews")
        }
    }

    private func loadCachedNews() {
        if let data = UserDefaults.standard.data(forKey: "cachedTopNews"),
           let articles = try? JSONDecoder().decode([NewsArticle].self, from: data) {
            topNews = articles
        }
    }
}
