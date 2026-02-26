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
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Reveal search UI with a downward swipe that starts near the top of the screen.
    func swipeDownToRevealSearch(
        enabled: Bool = true,
        topRegion: CGFloat = 180,
        minimumDistance: CGFloat = 68,
        action: @escaping () -> Void
    ) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    guard enabled else { return }
                    let startsNearTop = value.startLocation.y <= topRegion
                    let verticalDistance = value.translation.height
                    let horizontalDistance = abs(value.translation.width)
                    let isMostlyVertical = abs(verticalDistance) >= max(20, horizontalDistance * 1.35)
                    if startsNearTop && isMostlyVertical && verticalDistance >= minimumDistance {
                        action()
                    }
                }
        )
    }

    /// Dismiss active search UI with an upward swipe.
    func swipeUpToDismissSearch(
        enabled: Bool = true,
        topRegion: CGFloat = 260,
        minimumDistance: CGFloat = 54,
        action: @escaping () -> Void
    ) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    guard enabled else { return }
                    let startsNearTop = value.startLocation.y <= topRegion
                    let verticalDistance = value.translation.height
                    let horizontalDistance = abs(value.translation.width)
                    let isMostlyVertical = abs(verticalDistance) >= max(20, horizontalDistance * 1.35)
                    if startsNearTop && isMostlyVertical && verticalDistance <= -minimumDistance {
                        action()
                    }
                }
        )
    }
}
