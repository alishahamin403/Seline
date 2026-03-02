import SwiftUI

struct EmailCategoryFilterView: View {
    @Binding var selectedCategory: EmailCategory?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                EmailCategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    colorScheme: colorScheme
                ) {
                    HapticManager.shared.selection()
                    selectedCategory = nil
                }

                ForEach(EmailCategory.allCases, id: \.self) { category in
                    EmailCategoryChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category,
                        colorScheme: colorScheme
                    ) {
                        HapticManager.shared.selection()
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 22,
            highlightStrength: 0.35
        )
    }
}

struct EmailCategoryChip: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var chipForegroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.black : .white
        }
        return Color.appTextPrimary(colorScheme)
    }

    private var chipBackgroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.appTextPrimary(colorScheme)
        }
        return Color.appChip(colorScheme)
    }

    private var chipStrokeColor: Color {
        Color.appBorder(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                .foregroundColor(chipForegroundColor)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(chipBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(chipStrokeColor, lineWidth: isSelected ? 0 : 1)
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
