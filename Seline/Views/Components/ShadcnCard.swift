import SwiftUI

struct ShadcnCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
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
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 0 : 12,
            x: 0,
            y: colorScheme == .dark ? 0 : 4
        )
    }
}

struct ShadcnCardHeader: View {
    let title: String
    let subtitle: String?
    @Environment(\.colorScheme) var colorScheme

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            colorScheme == .dark ?
                Color.white.opacity(0.03) :
                Color.black.opacity(0.02)
        )
    }
}

struct ShadcnCardContent: View {
    let content: AnyView

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(16)
    }
}

struct ShadcnCardFooter: View {
    let content: AnyView
    @Environment(\.colorScheme) var colorScheme

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(16)
            .background(
                colorScheme == .dark ?
                    Color.white.opacity(0.03) :
                    Color.black.opacity(0.02)
            )
    }
}
