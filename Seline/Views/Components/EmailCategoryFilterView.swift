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
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
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
        return colorScheme == .dark ? Color.white.opacity(0.7) : Color.emailLightTextSecondary
    }

    private var chipBackgroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.emailLightTextPrimary
        }
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle
    }

    private var chipStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
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
