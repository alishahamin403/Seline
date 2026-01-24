import SwiftUI

struct EmailCategoryFilterView: View {
    @Binding var selectedCategory: EmailCategory?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EmailCategory.allCases, id: \.self) { category in
                    EmailCategoryChip(
                        category: category,
                        isSelected: selectedCategory == category,
                        colorScheme: colorScheme
                    ) {
                        HapticManager.shared.selection()
                        // Toggle behavior: tap to select, tap again to deselect
                        if selectedCategory == category {
                            selectedCategory = nil // Deselect to show all emails
                        } else {
                            selectedCategory = category // Select this category
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }
}

struct EmailCategoryChip: View {
    let category: EmailCategory
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.displayName)
                .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ?
                    .white :
                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ?
                            Color(red: 0.29, green: 0.29, blue: 0.29) :
                            (colorScheme == .dark ?
                                Color.white.opacity(0.1) :
                                Color.black.opacity(0.05))
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        EmailCategoryFilterView(selectedCategory: .constant(nil))
        EmailCategoryFilterView(selectedCategory: .constant(.primary))
        EmailCategoryFilterView(selectedCategory: .constant(.promotions))
        EmailCategoryFilterView(selectedCategory: .constant(.updates))
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}