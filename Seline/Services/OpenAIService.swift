import Foundation

class OpenAIService: ObservableObject {
    static let shared = OpenAIService()

    // TODO: Replace with your OpenAI API key
    // For security, consider using environment variables or secure storage
    private let apiKey = "YOUR_OPENAI_API_KEY_HERE"
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private init() {}

    enum SummaryError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case apiError(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from API"
            case .decodingError:
                return "Failed to decode API response"
            case .apiError(let message):
                return "API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }

    func summarizeEmail(subject: String, body: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        // Create the prompt for GPT
        let emailContent = """
        Subject: \(subject)

        Body: \(body)
        """

        let systemPrompt = """
        You are an AI assistant that summarizes emails. Your task is to create exactly 4 concise bullet points that capture the most important information from the email. Each bullet point should be a complete sentence and focus on key information, action items, deadlines, or important details. Format your response as exactly 4 bullet points, each starting with a bullet symbol (•).
        """

        let userPrompt = """
        Please summarize the following email in exactly 4 bullet points:

        \(emailContent)
        """

        // Create the request body
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "max_tokens": 300,
            "temperature": 0.3
        ]

        // Create the HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw SummaryError.networkError(error)
        }

        // Make the API call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw SummaryError.apiError(message)
                    } else {
                        throw SummaryError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                }
            }

            // Parse the response
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummaryError.decodingError
            }

            // Clean up the response and ensure it's properly formatted
            let cleanedSummary = cleanAndFormatSummary(content)
            return cleanedSummary

        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.networkError(error)
        }
    }

    private func cleanAndFormatSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var bulletPoints: [String] = []

        for line in lines {
            var cleanLine = line

            // Remove common bullet point prefixes
            if cleanLine.hasPrefix("• ") || cleanLine.hasPrefix("- ") || cleanLine.hasPrefix("* ") {
                cleanLine = String(cleanLine.dropFirst(2))
            } else if cleanLine.hasPrefix("•") || cleanLine.hasPrefix("-") || cleanLine.hasPrefix("*") {
                cleanLine = String(cleanLine.dropFirst(1))
            }

            // Remove numbered prefixes (1., 2., etc.)
            if let range = cleanLine.range(of: "^\\d+\\.\\s*", options: .regularExpression) {
                cleanLine = String(cleanLine[range.upperBound...])
            }

            cleanLine = cleanLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanLine.isEmpty {
                bulletPoints.append(cleanLine)
            }
        }

        // Ensure we have exactly 4 bullet points
        let finalBullets = Array(bulletPoints.prefix(4))

        // If we have fewer than 4, pad with generic points (shouldn't happen with proper prompting)
        while finalBullets.count < 4 && bulletPoints.count < 4 {
            if bulletPoints.count == 1 {
                bulletPoints.append("Additional details mentioned in the email")
            } else if bulletPoints.count == 2 {
                bulletPoints.append("Further information provided")
            } else if bulletPoints.count == 3 {
                bulletPoints.append("Email contains additional context")
            }
        }

        return finalBullets.joined(separator: ". ")
    }
}

// MARK: - Response Models (for future use if needed)
struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
}