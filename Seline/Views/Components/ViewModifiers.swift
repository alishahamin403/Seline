import SwiftUI

// MARK: - Presentation Background Modifier

struct PresentationBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationBackground(colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
        } else {
            content
        }
    }
}

extension View {
    func presentationBg() -> some View {
        self.modifier(PresentationBackgroundModifier())
    }
}
