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

    /// Navigation-style overlay push/pop used for home-sidebar destinations.
    static let navigationOverlayTransition = Animation.interactiveSpring(
        response: 0.34,
        dampingFraction: 0.92,
        blendDuration: 0.16
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

    /// Overlay dismiss — easeInOut for a natural, clean slide back
    static let overlayDismiss = Animation.easeInOut(duration: 0.28)
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

extension View {
    func allowsParentScrolling() -> some View {
        self
    }

    func scrollSafeTapAction(
        minimumDragDistance: CGFloat = 8,
        action: @escaping () -> Void
    ) -> some View {
        self.onTapGesture(perform: action)
    }
}
