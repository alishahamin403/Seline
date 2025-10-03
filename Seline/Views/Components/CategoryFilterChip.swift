import SwiftUI

struct CategoryFilterChip: View {
    let category: String
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            Text(category)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(
                    isSelected ?
                        .white :
                        (colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isSelected ?
                                (colorScheme == .dark ?
                                    Color(red: 0.40, green: 0.65, blue: 0.80) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                (colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                    Color.black.opacity(0.08))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isSelected ?
                                Color.clear :
                                (colorScheme == .dark ?
                                    Color.white.opacity(0.3) :
                                    Color.black.opacity(0.2)),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CategoryFilterView: View {
    @Binding var selectedCategory: String?
    let categories: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                CategoryFilterChip(
                    category: "All",
                    isSelected: selectedCategory == nil,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = nil
                        }
                    }
                )

                // Category chips
                ForEach(Array(categories).sorted(), id: \.self) { category in
                    CategoryFilterChip(
                        category: category,
                        isSelected: selectedCategory == category,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CategoryFilterView(
            selectedCategory: .constant(nil),
            categories: ["Restaurants", "Coffee Shops", "Shopping", "Healthcare", "Entertainment"]
        )

        CategoryFilterView(
            selectedCategory: .constant("Coffee Shops"),
            categories: ["Restaurants", "Coffee Shops", "Shopping", "Healthcare", "Entertainment"]
        )
    }
    .padding(.vertical)
    .background(Color.shadcnBackground(.light))
}
