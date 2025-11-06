import SwiftUI
import CoreLocation

// MARK: - Compact Dropdown Component

struct CompactDropdown: View {
    let label: String
    let options: [String]
    let selectedOption: String?
    let onSelect: (String) -> Void
    let colorScheme: ColorScheme

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onSelect(option)
                    }
                }) {
                    HStack {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if (option == "All" && selectedOption == nil) ||
                           (option != "All" && selectedOption == option) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        colorScheme == .dark ?
                            Color.white.opacity(0.08) :
                            Color.black.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        colorScheme == .dark ?
                            Color.white.opacity(0.12) :
                            Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Category Filter Slider

struct CategoryFilterSlider: View {
    @Binding var selectedCategory: String?
    let categories: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All" option
                FilterPillButton(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    colorScheme: colorScheme
                ) {
                    selectedCategory = nil
                }

                // Individual categories
                ForEach(categories, id: \.self) { category in
                    FilterPillButton(
                        title: category,
                        isSelected: selectedCategory == category,
                        colorScheme: colorScheme
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Pill Button

struct FilterPillButton: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var textColor: Color {
        if isSelected {
            return Color.white
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return Color.clear
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


#Preview {
    CategoryFilterSlider(
        selectedCategory: .constant(nil),
        categories: ["Restaurants", "Coffee Shops", "Shopping"]
    )
}
