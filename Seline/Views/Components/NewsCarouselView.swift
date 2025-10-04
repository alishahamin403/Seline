import SwiftUI

struct NewsCarouselView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var newsService = NewsService.shared
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            if newsService.isLoading && newsService.topNews.isEmpty {
                // Loading state
                HStack(alignment: .center, spacing: ShadcnSpacing.sm) {
                    Text("Loading news...")
                        .font(.shadcnTextXs)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .multilineTextAlignment(.center)

                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, ShadcnSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            } else if newsService.topNews.isEmpty {
                // Empty state
                Text("No news available")
                    .font(.shadcnTextXs)
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, ShadcnSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            } else {
                // News carousel
                VStack(spacing: 8) {
                    TabView(selection: $currentPage) {
                        ForEach(Array(newsService.topNews.enumerated()), id: \.element.id) { index, article in
                            NewsCardView(article: article, colorScheme: colorScheme)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 60)

                    // Custom page indicator dots
                    HStack(spacing: 6) {
                        ForEach(0..<newsService.topNews.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ?
                                    (colorScheme == .dark ? Color.white : Color.black) :
                                    (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                                )
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .padding(.vertical, ShadcnSpacing.sm)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            }
        }
        .task {
            await newsService.fetchTopWorldNews()
        }
    }
}

struct NewsCardView: View {
    let article: NewsArticle
    let colorScheme: ColorScheme

    var body: some View {
        Button(action: {
            if let url = URL(string: article.url) {
                UIApplication.shared.open(url)
            }
        }) {
            VStack(spacing: 4) {
                // Source name
                Text(article.source)
                    .font(.shadcnTextXs)
                    .foregroundColor(colorScheme == .dark ?
                        Color(red: 0.518, green: 0.792, blue: 0.914) :
                        Color(red: 0.20, green: 0.34, blue: 0.40))
                    .textCase(.uppercase)
                    .fontWeight(.semibold)

                // News title
                Text(article.title)
                    .font(.shadcnTextXs)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 16) {
        NewsCarouselView()
    }
    .padding(.horizontal, 20)
    .background(Color.shadcnBackground(.light))
}
