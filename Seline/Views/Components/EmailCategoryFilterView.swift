import SwiftUI

struct EmailCategoryFilterView: View {
    @Binding var selectedCategory: EmailCategory?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(EmailCategory.allCases, id: \.self) { category in
                CategoryFilterButton(
                    category: category,
                    selectedCategory: $selectedCategory,
                    colorScheme: colorScheme
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

struct CategoryFilterButton: View {
    let category: EmailCategory
    @Binding var selectedCategory: EmailCategory?
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedCategory == category
    }

    private var selectedColor: Color {
        if colorScheme == .dark {
            // Light blue for dark mode - #84cae9
            return Color(red: 0.518, green: 0.792, blue: 0.914)
        } else {
            // Dark blue for light mode - #345766
            return Color(red: 0.20, green: 0.34, blue: 0.40)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return selectedColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
        }
        return Color.clear
    }

    var body: some View {
        Button(action: {
            // Toggle behavior: tap to select, tap again to deselect
            if selectedCategory == category {
                selectedCategory = nil // Deselect to show all emails
            } else {
                selectedCategory = category // Select this category
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))

                Text(category.displayName)
                    .font(FontManager.geist(size: .caption, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(
                isSelected ? selectedColor : Color.gray
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    VStack(spacing: 20) {
        EmailCategoryFilterView(selectedCategory: .constant(nil))
        EmailCategoryFilterView(selectedCategory: .constant(.important))
        EmailCategoryFilterView(selectedCategory: .constant(.promotional))
        EmailCategoryFilterView(selectedCategory: .constant(.updates))
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}