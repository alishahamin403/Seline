import Foundation

struct FunFactResponse: Codable {
    let id: String
    let text: String
    let source: String
    let sourceUrl: String
    let language: String
    let permalink: String

    enum CodingKeys: String, CodingKey {
        case id, text, source, language, permalink
        case sourceUrl = "source_url"
    }
}

@MainActor
class FunFactsService: ObservableObject {
    static let shared = FunFactsService()

    @Published var currentFact: String = ""
    @Published var isLoading: Bool = false

    private let apiURL = "https://uselessfacts.jsph.pl/api/v2/facts/random?language=en"
    private var timer: Timer?
    private let fetchInterval: TimeInterval = 3 * 60 * 60 // 3 hours in seconds

    // Fallback facts in case API fails (all under 4 lines)
    private let fallbackFacts = [
        "There are six million parts in the Boeing 747-400.",
        "The average person checks email 74 times per day.",
        "A single Google search uses the same energy as a 60-watt bulb for 17 seconds.",
        "The first email was sent in 1971 by Ray Tomlinson to himself.",
        "NASA's internet connection speed is 91GB per second.",
        "Octopuses have three hearts and blue blood.",
        "A group of flamingos is called a 'flamboyance'.",
        "Honey never spoils. Archaeologists have found pots of honey in ancient tombs over 3,000 years old.",
        "The human brain uses about 20% of the body's total energy.",
        "A day on Venus is longer than its year."
    ]

    private init() {
        // Start with a fallback fact
        currentFact = fallbackFacts.randomElement() ?? "Loading amazing facts..."
        startPeriodicFetching()
    }

    func startPeriodicFetching() {
        // Fetch immediately
        Task {
            await fetchRandomFact()
        }

        // Set up timer for every 3 hours
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fetchInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.fetchRandomFact()
            }
        }
    }

    func fetchRandomFact() async {
        isLoading = true

        guard let url = URL(string: apiURL) else {
            print("Invalid URL")
            useRandomFallbackFact()
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("API request failed")
                useRandomFallbackFact()
                isLoading = false
                return
            }

            let factResponse = try JSONDecoder().decode(FunFactResponse.self, from: data)

            // Clean up the fact text (remove extra whitespace, etc.)
            let cleanedFact = factResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanedFact.isEmpty {
                currentFact = truncateToFourLines(cleanedFact)
                print("✅ New fun fact fetched: \(cleanedFact.prefix(50))...")
            } else {
                useRandomFallbackFact()
            }

        } catch {
            print("Error fetching fun fact: \(error)")
            useRandomFallbackFact()
        }

        isLoading = false
    }

    private func useRandomFallbackFact() {
        // Use a different fallback fact than the current one
        let availableFacts = fallbackFacts.filter { $0 != currentFact }
        currentFact = availableFacts.randomElement() ?? fallbackFacts.first ?? "Amazing facts coming soon!"
        print("📱 Using fallback fact: \(currentFact.prefix(50))...")
    }

    func manualRefresh() {
        Task {
            await fetchRandomFact()
        }
    }

    private func truncateToFourLines(_ text: String) -> String {
        // Approximate 40 characters per line for 4 lines max (160 characters)
        // This accounts for text-xs font size in the tile width
        let maxCharacters = 160

        if text.count <= maxCharacters {
            return text
        }

        // Find the last complete sentence within the limit
        let truncated = String(text.prefix(maxCharacters))

        // Find the last sentence ending (period, exclamation, or question mark)
        let sentenceEnders: [Character] = [".", "!", "?"]
        for i in truncated.indices.reversed() {
            if sentenceEnders.contains(truncated[i]) {
                return String(truncated.prefix(through: i))
            }
        }

        // If no sentence ending found, find last complete word
        if let lastSpaceIndex = truncated.lastIndex(of: " ") {
            return String(truncated.prefix(upTo: lastSpaceIndex)) + "..."
        }

        // Fallback: just truncate with ellipsis
        return String(text.prefix(maxCharacters - 3)) + "..."
    }

    deinit {
        timer?.invalidate()
    }
}