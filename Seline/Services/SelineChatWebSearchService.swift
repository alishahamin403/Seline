import Foundation

struct SelineChatWebSearchResponse {
    let summary: String
    let citations: [SelineChatWebCitation]
}

/// Performs web searches using Gemini's built-in Google Search grounding.
/// Triggered when a chat query needs external/factual information (parking,
/// directions, hours, flight info, etc.) not present in personal data.
@MainActor
final class SelineChatWebSearchService {
    static let shared = SelineChatWebSearchService()
    private init() {}

    private let model = "gemini-2.0-flash"

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(Config.geminiAPIKey)")!
    }

    // MARK: - Trigger Detection

    /// Returns true when the query likely needs live web data rather than personal data alone.
    func needsWebSearch(for frame: SelineChatQuestionFrame) -> Bool {
        let q = frame.normalizedQuestion.lowercased()
        let externalKeywords = [
            // Parking / directions
            "parking", "park at", "park near", "where to park",
            "directions", "how to get there", "how do i get",
            // Airports / travel logistics
            "arrival time", "departure time", "how long is the flight",
            "layover", "connecting flight", "which gate", "what gate",
            "terminal", "baggage claim", "check in", "check-in",
            "airport parking", "short term parking", "long term parking",
            "shuttle", "transit", "uber to airport", "taxi to airport",
            // Hours / open status
            "is it open", "opening hours", "what time does it open", "what time does it close",
            "store hours", "business hours",
            // Distance / travel time
            "how far is", "how long does it take to get", "drive time", "transit time",
            // Weather
            "weather", "forecast", "temperature", "rain", "snow",
            // Costs / prices
            "how much does it cost", "price of", "cost of", "fee", "admission",
            // Find / locate
            "where is the nearest", "where can i find", "what is the address of",
            // General knowledge that's time-sensitive
            "is the airport", "flight status", "flight delay", "delayed", "cancelled flight"
        ]
        return externalKeywords.contains(where: { q.contains($0) })
    }

    // MARK: - Search

    /// Runs a Google Search-grounded Gemini request and returns structured text plus citations.
    func searchStructured(query: String) async -> SelineChatWebSearchResponse? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": query]]]
            ],
            "tools": [
                ["googleSearch": [:]]
            ],
            "generationConfig": [
                "maxOutputTokens": 512
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return extractResponse(from: data)
        } catch {
            return nil
        }
    }

    /// Backward-compatible helper for callers that only want the summary text.
    func search(query: String) async -> String? {
        await searchStructured(query: query)?.summary
    }

    // MARK: - Parsing

    private func extractResponse(from data: Data) -> SelineChatWebSearchResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first else { return nil }

        let summary: String = {
            guard let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                return ""
            }
            return parts.compactMap { $0["text"] as? String }.joined()
        }()

        var citations: [SelineChatWebCitation] = []
        var seenURLs = Set<String>()

        if let groundingMetadata = first["groundingMetadata"] as? [String: Any],
           let groundingChunks = groundingMetadata["groundingChunks"] as? [[String: Any]] {
            for chunk in groundingChunks {
                guard let web = chunk["web"] as? [String: Any],
                      let url = web["uri"] as? String,
                      !url.isEmpty,
                      seenURLs.insert(url).inserted else {
                    continue
                }

                let title = (web["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let source = URL(string: url)?.host

                citations.append(
                    SelineChatWebCitation(
                        title: title?.isEmpty == false ? title! : (source ?? "Web result"),
                        url: url,
                        source: source
                    )
                )
            }
        }

        guard !summary.isEmpty || !citations.isEmpty else { return nil }
        return SelineChatWebSearchResponse(summary: summary, citations: citations)
    }
}
