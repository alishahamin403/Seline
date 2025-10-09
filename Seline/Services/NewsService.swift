import Foundation
import UIKit

class NewsService: ObservableObject {
    static let shared = NewsService()

    @Published var topNews: [NewsArticle] = []
    @Published var isLoading: Bool = false
    @Published var currentCategory: NewsCategory = .general

    // App state tracking
    private var isAppActive = false
    private var newsRefreshTimer: Timer?

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

        // Set up app lifecycle observers instead of auto-starting timer
        setupAppLifecycleObservers()
    }

    deinit {
        newsRefreshTimer?.invalidate()
    }

    func fetchNews(for category: NewsCategory) async {
        // Check if we fetched this category within the last hour
        let cacheKey = "lastNewsFetchDate_\(category.rawValue)"
        if let lastFetchDate = UserDefaults.standard.object(forKey: cacheKey) as? Date {
            let hoursSinceLastFetch = Date().timeIntervalSince(lastFetchDate) / 3600
            if hoursSinceLastFetch < 1.0 && !topNews.isEmpty && currentCategory == category {
                return // Already fetched within the last hour
            }
        }

        await MainActor.run {
            isLoading = true
            currentCategory = category
        }

        // Fetch top 10 news from US with category filter to ensure we get 5 good ones
        if let articles = await fetchNewsForCategory(category, limit: 10) {
            // Filter out articles without descriptions, then take top 5
            let validArticles = articles.filter { article in
                article.description != nil && !article.description!.isEmpty
            }
            let sortedArticles = validArticles.sorted { $0.publishedAt > $1.publishedAt }.prefix(5)

            await MainActor.run {
                self.topNews = Array(sortedArticles)
                self.isLoading = false

                // Cache the results
                cacheNews(Array(sortedArticles), for: category)
                UserDefaults.standard.set(Date(), forKey: cacheKey)
            }
        } else {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func fetchTopWorldNews() async {
        await fetchNews(for: .general)
    }

    // MARK: - App Lifecycle Management

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        print("📰 NewsService: App became active - NO automatic refresh (manual only)")
        isAppActive = true
        // REMOVED: No automatic refresh timer - only manual refresh when user opens home page
    }

    @objc private func appDidEnterBackground() {
        print("📰 NewsService: App entered background")
        isAppActive = false
        stopHourlyRefresh()
    }

    private func stopHourlyRefresh() {
        newsRefreshTimer?.invalidate()
        newsRefreshTimer = nil
        print("🛑 NewsService: Refresh timer stopped")
    }

    private func fetchNewsForCategory(_ category: NewsCategory, limit: Int = 5) async -> [NewsArticle]? {
        var urlString = "\(baseURL)?country=us&pageSize=\(limit)&apiKey=\(apiKey)"

        // Add category parameter if not general
        if category != .general {
            urlString += "&category=\(category.rawValue)"
        }

        guard let url = URL(string: urlString) else {
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

                return NewsArticle(
                    title: article.title,
                    description: article.description,
                    country: "United States",
                    publishedAt: publishedDate,
                    url: article.url,
                    source: article.source.name
                )
            }
        } catch {
            print("Failed to fetch news for \(category.rawValue): \(error)")
            return nil
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

    private func cacheNews(_ articles: [NewsArticle], for category: NewsCategory) {
        if let encoded = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(encoded, forKey: "cachedTopNews_\(category.rawValue)")
        }
    }

    private func loadCachedNews() {
        // Load cached news for general category by default
        if let data = UserDefaults.standard.data(forKey: "cachedTopNews_general"),
           let articles = try? JSONDecoder().decode([NewsArticle].self, from: data) {
            topNews = articles
        }
    }
}
