import SwiftUI

struct HomeSectionButton: View {
    let title: String
    let unreadCount: Int?
    @Environment(\.colorScheme) var colorScheme

    init(title: String, unreadCount: Int? = nil) {
        self.title = title
        self.unreadCount = unreadCount
    }

    var body: some View {
        Button(action: {
            // TODO: Add navigation logic based on title
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 24, weight: .bold)) // Smaller font size
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()

                if let unreadCount = unreadCount, unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            HomeSectionButton(title: "EMAIL")
            HomeSectionButton(title: "EVENTS")
        }
        HStack(spacing: 16) {
            HomeSectionButton(title: "NOTES")
            HomeSectionButton(title: "MAPS")
        }
    }
    .padding(.horizontal, 20)
    .background(Color.shadcnBackground(.light))
}