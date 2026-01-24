import SwiftUI

struct MetricTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String
    @Environment(\.colorScheme) var colorScheme


    var body: some View {
        VStack(spacing: 12) {
            // Icon - bigger size
            Image(systemName: icon)
                .font(FontManager.geist(size: 26, weight: .medium))
                .foregroundColor(Color.shadcnForeground(colorScheme))

            // Only show the number value
            if !value.isEmpty {
                Text(value)
                    .font(FontManager.geist(size: 19, weight: .regular))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(12)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
}

#Preview {
    LazyVGrid(columns: [
        GridItem(.flexible()),
        GridItem(.flexible())
    ], spacing: 16) {
        MetricTile(
            icon: "envelope",
            title: "Unread",
            subtitle: "Emails",
            value: "0"
        )

        MetricTile(
            icon: "calendar",
            title: "Events",
            subtitle: "Today",
            value: "0"
        )

        MetricTile(
            icon: "checkmark.circle",
            title: "Todos",
            subtitle: "Today",
            value: "2"
        )

        MetricTile(
            icon: "star",
            title: "Important",
            subtitle: "Items",
            value: "5"
        )
    }
    .padding()
}