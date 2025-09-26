import SwiftUI

struct MetricTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String
    @Environment(\.colorScheme) var colorScheme


    var body: some View {
        VStack(spacing: 12) {
            // Icon - smaller size
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Color.shadcnForeground(colorScheme))

            // Only show the number value
            if !value.isEmpty {
                Text(value)
                    .font(.shadcnTextLg)
                    .fontWeight(.regular)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 8 : 12,
            x: 0,
            y: colorScheme == .dark ? 3 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.04) : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 6,
            x: 0,
            y: colorScheme == .dark ? 1 : 2
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.02) : .clear,
            radius: colorScheme == .dark ? 8 : 0,
            x: 0,
            y: colorScheme == .dark ? 2 : 0
        )
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