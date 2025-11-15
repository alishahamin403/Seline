import Foundation
import GoogleSignIn

/// Service for handling Gmail labels and label-related operations
class GmailLabelService {
    static let shared = GmailLabelService()

    private init() {}

    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    // MARK: - Public Methods

    /// Fetch all custom labels from Gmail (excludes system labels like INBOX, SENT, etc.)
    func fetchAllCustomLabels() async throws -> [GmailLabel] {
        print("🔍 GmailLabelService.fetchAllCustomLabels() called")

        print("🔄 Refreshing access token if needed...")
        try await refreshAccessTokenIfNeeded()
        print("✅ Token refresh complete")

        print("👤 Checking for authenticated Google user...")
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            print("❌ No Google user authenticated!")
            throw GmailAPIError.notAuthenticated
        }
        print("✅ Google user found: \(user.profile?.email ?? "unknown")")

        let accessToken = user.accessToken.tokenString
        print("🔑 Access token retrieved")

        guard let url = URL(string: "\(baseURL)/labels") else {
            print("❌ Invalid URL constructed")
            throw GmailAPIError.invalidURL
        }
        print("📍 API URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📡 Making API request to fetch labels...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response received")
            throw GmailAPIError.invalidResponse
        }

        print("📊 HTTP Status Code: \(httpResponse.statusCode)")
        guard httpResponse.statusCode == 200 else {
            let errorMessage = "Failed to fetch labels (HTTP \(httpResponse.statusCode))"
            print("❌ \(errorMessage)")
            throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
        }

        print("📦 Parsing JSON response...")
        let labelsResponse = try JSONDecoder().decode(GmailLabelsResponse.self, from: data)
        print("✅ JSON decoded successfully")

        let allLabels = labelsResponse.labels ?? []
        print("📋 Total labels from API: \(allLabels.count)")

        for label in allLabels {
            print("  - API Label: '\(label.name)' (ID: \(label.id))")
        }

        // Filter out system labels (they start with "CATEGORY_" or are specific system labels)
        let customLabels = allLabels.filter { label in
            let systemLabels = ["INBOX", "SENT", "DRAFT", "TRASH", "SPAM", "UNREAD", "IMPORTANT", "STARRED"]
            let isSystemLabel = systemLabels.contains(label.id)
            let isCategory = label.id.starts(with: "CATEGORY_")
            return !isSystemLabel && !isCategory
        }

        print("🎯 Custom labels after filtering: \(customLabels.count)")
        for label in customLabels {
            print("  ✓ Custom Label: '\(label.name)' (ID: \(label.id))")
        }

        return customLabels
    }

    /// Fetch emails in a specific label with pagination
    /// - Parameters:
    ///   - labelId: The Gmail label ID
    ///   - pageToken: Optional token for pagination
    ///   - maxResults: Maximum number of results per page (default 50, max 100)
    /// - Returns: Tuple of (message IDs, nextPageToken)
    func fetchEmailsInLabel(
        labelId: String,
        pageToken: String? = nil,
        maxResults: Int = 50
    ) async throws -> (messageIds: [String], nextPageToken: String?) {
        try await refreshAccessTokenIfNeeded()

        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        let accessToken = user.accessToken.tokenString

        var components = URLComponents(string: "\(baseURL)/messages")
        components?.queryItems = [
            URLQueryItem(name: "labelIds", value: labelId),
            URLQueryItem(name: "maxResults", value: String(min(maxResults, 100))),
            URLQueryItem(name: "fields", value: "messages(id),nextPageToken")
        ]

        if let pageToken = pageToken {
            components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        guard let url = components?.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        // Handle 204 No Content (label has no emails) as a valid success
        if httpResponse.statusCode == 204 {
            print("📭 Label is empty (HTTP 204 - No Content)")
            return ([], nil)
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = "Failed to fetch emails in label (HTTP \(httpResponse.statusCode))"
            throw GmailAPIError.apiError(httpResponse.statusCode, errorMessage)
        }

        let messageList = try JSONDecoder().decode(GmailMessagesList.self, from: data)
        let messageIds = messageList.messages?.map { $0.id } ?? []

        return (messageIds, messageList.nextPageToken)
    }

    /// Get the label color from Gmail label metadata
    func getLabelColor(from label: GmailLabel) -> String? {
        // Gmail uses backgroundColor property for the label color
        // If available, return it; otherwise return nil
        return label.color?.backgroundColor
    }

    // MARK: - Private Methods

    private func refreshAccessTokenIfNeeded() async throws {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAPIError.notAuthenticated
        }

        let currentToken = user.accessToken
        let expirationDate = currentToken.expirationDate

        if let expirationDate = expirationDate, expirationDate.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
        }
    }

    private func refreshAccessToken() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error = error {
                    print("❌ Failed to refresh token: \(error.localizedDescription)")
                    continuation.resume(throwing: GmailAPIError.notAuthenticated)
                    return
                }

                guard user != nil else {
                    print("❌ No user after refresh attempt")
                    continuation.resume(throwing: GmailAPIError.notAuthenticated)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }
}

// MARK: - Data Models

/// Represents a Gmail label with metadata
struct GmailLabel: Codable, Identifiable {
    let id: String
    let name: String
    let messageListVisibility: String?
    let labelListVisibility: String?
    let type: String? // "system" or "user"
    let messagesTotal: Int?
    let messagesUnread: Int?
    let color: GmailLabelColor?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case messageListVisibility
        case labelListVisibility
        case type
        case messagesTotal
        case messagesUnread
        case color
    }
}

/// Represents the color of a Gmail label
struct GmailLabelColor: Codable {
    let textColor: String?     // RGB color code (e.g., "#FFFFFF")
    let backgroundColor: String? // RGB color code (e.g., "#5f6368")

    enum CodingKeys: String, CodingKey {
        case textColor
        case backgroundColor
    }
}

/// Response from Gmail labels API
struct GmailLabelsResponse: Codable {
    let labels: [GmailLabel]?

    enum CodingKeys: String, CodingKey {
        case labels
    }
}
