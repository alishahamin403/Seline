import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String?
    @Environment(\.colorScheme) var colorScheme

    let icons: [(name: String, label: String)] = [
        ("house.fill", "Home"),
        ("briefcase.fill", "Work"),
        ("dumbbell.fill", "Gym"),
        ("fork.knife", "Restaurant"),
        ("tree.fill", "Park"),
        ("heart.fill", "Medical"),
        ("bag.fill", "Shop"),
        ("book.fill", "School"),
        ("star.fill", "Favorite"),
        ("cup.and.saucer", "Coffee"),
        ("car.fill", "Car"),
        ("airplane", "Travel"),
        ("film.fill", "Entertainment"),
        ("gamecontroller.fill", "Gaming"),
        ("music.note", "Music"),
        ("camera.fill", "Photo"),
        ("bicycle", "Cycling"),
        ("mappin.circle.fill", "Location"),
        ("building.2.fill", "Building"),
        ("flame.fill", "Fire"),
        ("scissors", "Haircut"),
        ("building.fill", "Hotel"),
        ("heart.circle.fill", "Health"),
        ("person.fill", "People"),
        ("clock.fill", "Time"),
    ]

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Icon")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(icons, id: \.name) { icon in
                    Button(action: {
                        selectedIcon = icon.name
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: icon.name)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(height: 32)

                            Text(icon.label)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selectedIcon == icon.name ?
                                    (colorScheme == .dark ? Color.blue.opacity(0.3) : Color.blue.opacity(0.15)) :
                                    (colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedIcon == icon.name ? Color.blue : (colorScheme == .dark ? Color.clear : Color.gray.opacity(0.2)),
                                    lineWidth: selectedIcon == icon.name ? 2 : 1
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }
}

#Preview {
    IconPickerView(selectedIcon: .constant("house.fill"))
        .background(Color.black)
}
