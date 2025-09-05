import SwiftUI

struct PreviewSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    let destination: AnyView
    let content: Content

    init(title: String, icon: String, count: Int, destination: AnyView, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.count = count
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            NavigationLink(destination: destination) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.accentColor)

                    // Title and count
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("\(count) item\(count == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            // Content
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: Color.black.opacity(0.06),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
}
