import SwiftUI

struct NewsCarouselView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var newsService = NewsService.shared
    @State private var currentPage = 0
    @State private var selectedCategory: NewsCategory = .general

    var body: some View {
        VStack(spacing: 0) {
            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NewsCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            colorScheme: colorScheme
                        ) {
                            HapticManager.shared.selection()
                            selectedCategory = category
                            Task {
                                await newsService.fetchNews(for: category)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
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
                    .frame(height: 50)

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
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            }
        }
        .task {
            await newsService.fetchNews(for: selectedCategory)
        }
    }
}

struct CategoryChip: View {
    let category: NewsCategory
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color.white :
                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ?
                            Color(red: 0.2, green: 0.2, blue: 0.2) :
                            (colorScheme == .dark ?
                                Color.white.opacity(0.1) :
                                Color.black.opacity(0.05))
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
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
                // News title
                Text(article.title)
                    .font(.shadcnTextXs)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
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
