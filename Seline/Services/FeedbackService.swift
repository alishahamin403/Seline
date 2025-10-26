import Foundation

class FeedbackService: ObservableObject {
    static let shared = FeedbackService()

    @Published var feedbackSent = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let feedbackEmail = "alishah.amin96@gmail.com"
    // Using Resend API (free email service) - get your API key at https://resend.com
    private let resendAPIKey = "re_j4zuvPZd_N8ZeTB5aCiN1xYrk6mzQbZYo"
    private let resendBaseURL = "https://api.resend.com"

    func sendFeedback(message: String) async {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)

        guard !trimmedMessage.isEmpty else {
            await MainActor.run {
                self.errorMessage = "Please enter your feedback"
                self.showError = true
            }
            return
        }

        guard trimmedMessage.count <= 500 else {
            await MainActor.run {
                self.errorMessage = "Feedback must be 500 characters or less"
                self.showError = true
            }
            return
        }

        // Send email via Resend API
        do {
            let emailPayload: [String: Any] = [
                "from": "feedback@seline.app",
                "to": feedbackEmail,
                "subject": "New Feedback from Seline User",
                "html": """
                <h2>New User Feedback</h2>
                <p><strong>Timestamp:</strong> \(ISO8601DateFormatter().string(from: Date()))</p>
                <hr />
                <p><strong>Message:</strong></p>
                <p>\(trimmedMessage.replacingOccurrences(of: "\n", with: "<br />"))</p>
                """
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: emailPayload)

            guard let url = URL(string: "\(resendBaseURL)/emails") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(resendAPIKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            await MainActor.run {
                self.feedbackSent = true
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to send feedback. Please try again."
                self.showError = true
            }
            print("Feedback error: \(error)")
        }
    }
}
