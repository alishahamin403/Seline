import SwiftUI

/// Service to fetch company logos based on the company name
struct CompanyLogoProvider {
    
    /// Returns a URL for the company logo if likely available, or nil
    static func logoUrl(for companyName: String) -> URL? {
        // Clean the company name
        let query = cleanCompanyName(companyName)
        guard !query.isEmpty else { return nil }
        
        // Use Clearbit's logo API (free for personal use, commonly used for this)
        // Format: https://logo.clearbit.com/{domain}
        // Since we don't have the domain, we have to guess or use a service that searches.
        // A better alternative that takes a name is using a search-based assumption or a favicon grabber if we had a domain.
        // For this implementation, we will try to construct a domain guess.
        
        let link = "https://logo.clearbit.com/\(query.lowercased().replacingOccurrences(of: " ", with: "")).com"
        return URL(string: link)
    }
    
    private static func cleanCompanyName(_ name: String) -> String {
        return name
            .components(separatedBy: "-").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// A view that attempts to load a company logo, falling back to a default icon
struct CompanyLogoView: View {
    let companyName: String
    let fallbackIcon: String
    @State private var useFallback = false
    
    var body: some View {
        let url = CompanyLogoProvider.logoUrl(for: companyName)
        
        Group {
            if useFallback || url == nil {
                Text(fallbackIcon)
                    .font(FontManager.geist(size: 16, weight: .regular))
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(Circle())
                    } else if phase.error != nil {
                        // Error loading, switch to fallback
                        Color.clear
                            .onAppear { useFallback = true }
                    } else {
                        // Loading state
                        Color.gray.opacity(0.1)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}
