import SwiftUI

struct ShadcnAccordionItem<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) var colorScheme

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    HapticManager.shared.selection()
                }
            }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.white
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Content
            if isExpanded {
                content
                    .padding(16)
                    .background(
                        colorScheme == .dark ?
                            Color.white.opacity(0.02) :
                            Color.black.opacity(0.01)
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    colorScheme == .dark ?
                        Color.white.opacity(0.1) :
                        Color.black.opacity(0.05),
                    lineWidth: 1
                )
        )
    }
}
