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
        ("coffee", "Coffee"),
        ("utensils", "Food"),
        ("car.fill", "Car"),
        ("train.fill", "Transit"),
        ("airplane", "Travel"),
        ("movieclapper.fill", "Entertainment"),
        ("gamecontroller.fill", "Gaming"),
        ("music.note", "Music"),
        ("camera.fill", "Photo"),
        ("bicycle", "Cycling"),
        ("mappin.circle.fill", "Location"),
        ("building.2.fill", "Mosque"),
        ("hamburger", "Burger"),
        ("fork.knife.circle.fill", "Pasta"),
        ("burrito", "Shawarma"),
        ("pizza", "Pizza"),
        ("chef.hat", "Jamaican"),
        ("steak", "Steak"),
        ("sun.max.fill", "Mexican"),
        ("chopsticks", "Chinese"),
        ("flame.fill", "Smoke"),
        ("scissors", "Haircut"),
        ("tooth.fill", "Dental"),
        ("building.fill", "Hotel"),
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
                                .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))
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
                                    (colorScheme == .dark ? Color.blue.opacity(0.3) : Color.blue.opacity(0.1)) :
                                    (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedIcon == icon.name ? Color.blue : Color.clear,
                                    lineWidth: 2
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
