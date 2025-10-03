import SwiftUI

struct MotivationalGreeting: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var dailyQuote: String = ""
    @State private var isLoading = true

    private var userName: String {
        authManager.currentUser?.profile?.name ?? "User"
    }

    var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                Text("Loading...")
                    .font(FontManager.geist(size: 20, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            } else {
                Text(dailyQuote + ",")
                    .font(FontManager.geist(size: 20, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(userName)
                    .font(FontManager.geist(size: 20, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            await fetchDailyQuote()
        }
    }

    private func fetchDailyQuote() async {
        // Check if we have a cached quote for today
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        let cacheKey = "dailyQuote_\(todayString)"

        // Try to get cached quote
        if let cachedQuote = UserDefaults.standard.string(forKey: cacheKey) {
            dailyQuote = cachedQuote
            isLoading = false
            return
        }

        // Fetch new quote from API
        guard let url = URL(string: "https://zenquotes.io/api/random") else {
            dailyQuote = "Survive"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstQuote = json.first,
               let quoteText = firstQuote["q"] as? String {

                // Extract first 3 words or less
                let words = quoteText.split(separator: " ").prefix(3)
                let shortQuote = words.joined(separator: " ").replacingOccurrences(of: ".", with: "")

                dailyQuote = shortQuote

                // Cache the quote for today
                UserDefaults.standard.set(shortQuote, forKey: cacheKey)
            } else {
                dailyQuote = "Survive"
            }
        } catch {
            print("Error fetching quote: \(error)")
            dailyQuote = "Survive"
        }

        isLoading = false
    }
}

#Preview {
    MotivationalGreeting()
        .environmentObject(AuthenticationManager.shared)
        .padding()
}
