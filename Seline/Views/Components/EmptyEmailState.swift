import SwiftUI

struct EmptyEmailState: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Circle()
                .fill(Color.shadcnCard(colorScheme).opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: icon)
                        .font(FontManager.geist(size: 32, weight: .medium))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                )

            // Text content
            VStack(spacing: 8) {
                Text(title)
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(FontManager.geist(size: .body, weight: .regular))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 40)
    }
}

#Preview {
    VStack(spacing: 40) {
        EmptyEmailState(
            icon: "envelope",
            title: "No emails loaded",
            subtitle: "Pull down to refresh"
        )

        EmptyEmailState(
            icon: "checkmark.circle",
            title: "All caught up!",
            subtitle: "No new emails today"
        )

        EmptyEmailState(
            icon: "magnifyingglass",
            title: "No results found",
            subtitle: "Try adjusting your search terms"
        )
    }
    .background(Color.shadcnBackground(.light))
}