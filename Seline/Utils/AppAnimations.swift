import SwiftUI

// MARK: - Custom Animation Extensions
// Modern spring-based animations for smooth, natural-feeling transitions

extension Animation {
    /// Smooth tab transition animation
    static let smoothTabTransition = Animation.spring(
        response: 0.35,
        dampingFraction: 0.8,
        blendDuration: 0.1
    )
    
    /// Sheet presentation animation
    static let sheetPresentation = Animation.spring(
        response: 0.4,
        dampingFraction: 0.85
    )
    
    /// Card transition animation
    static let cardTransition = Animation.spring(
        response: 0.3,
        dampingFraction: 0.75
    )
    
    /// Quick interaction animation
    static let quickInteraction = Animation.spring(
        response: 0.25,
        dampingFraction: 0.7
    )
    
    /// Smooth scale animation
    static let smoothScale = Animation.spring(
        response: 0.3,
        dampingFraction: 0.75
    )
    
    /// Gentle fade animation
    static let gentleFade = Animation.easeInOut(duration: 0.2)
}

// MARK: - Presentation Modifiers

/// ViewModifier that conditionally applies iOS 16.4+ presentation modifiers
struct PresentationModifiers: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationCornerRadius(20)
                .presentationBackgroundInteraction(.enabled)
        } else {
            content
        }
    }
}

// MARK: - Scroll Gesture Helpers

private struct ScrollSafeTapModifier: ViewModifier {
    let minimumDragDistance: CGFloat
    let action: () -> Void

    @State private var isDragGestureActive = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if abs(value.translation.width) > minimumDragDistance ||
                        abs(value.translation.height) > minimumDragDistance {
                        isDragGestureActive = true
                    }
                }
                .onEnded { value in
                    defer { isDragGestureActive = false }

                    let moved = abs(value.translation.width) > minimumDragDistance ||
                        abs(value.translation.height) > minimumDragDistance
                    guard !moved && !isDragGestureActive else { return }
                    action()
                }
        )
    }
}

extension View {
    /// Makes buttons and interactive elements allow scroll gestures to pass through to parent ScrollView
    /// This prevents buttons from blocking scrolling when dragging on them, even immediately after a tap
    /// Uses simultaneous gesture recognition so the parent ScrollView can still win vertical scrolling
    func allowsParentScrolling() -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { _ in }
                .onEnded { _ in }
        )
    }

    /// Executes tap action only when finger movement stays below threshold.
    /// This prevents accidental row opens when the user intended to scroll.
    func scrollSafeTapAction(
        minimumDragDistance: CGFloat = 8,
        action: @escaping () -> Void
    ) -> some View {
        self.modifier(ScrollSafeTapModifier(minimumDragDistance: minimumDragDistance, action: action))
    }
}
