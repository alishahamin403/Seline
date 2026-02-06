import SwiftUI

// MARK: - Navigation Transition Styles
// Smooth spring-based transitions for navigation and presentations

extension AnyTransition {
    /// Hero-like slide transition with spring animation
    static var heroSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// Scale and fade transition for modal presentations
    static var modalPresentation: AnyTransition {
        .scale(scale: 0.95)
            .combined(with: .opacity)
    }

    /// Bottom sheet slide-up transition
    static var bottomSheet: AnyTransition {
        .move(edge: .bottom)
            .combined(with: .opacity)
    }

    /// Card flip transition
    static var cardFlip: AnyTransition {
        .modifier(
            active: FlipModifier(angle: 90, axis: (x: 0, y: 1, z: 0)),
            identity: FlipModifier(angle: 0, axis: (x: 0, y: 1, z: 0))
        )
    }
}

// MARK: - Custom Transition Modifiers

struct FlipModifier: ViewModifier {
    let angle: Double
    let axis: (x: CGFloat, y: CGFloat, z: CGFloat)

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: axis,
                perspective: 0.5
            )
            .opacity(angle == 0 ? 1 : 0)
    }
}

// MARK: - View Extensions for Smooth Navigation

extension View {
    /// Apply smooth spring animation to navigation transitions
    func smoothNavigation() -> some View {
        self.animation(.spring(response: 0.35, dampingFraction: 0.8), value: UUID())
    }

    /// Apply modal presentation animation
    func modalAnimation() -> some View {
        self.animation(.spring(response: 0.4, dampingFraction: 0.85), value: UUID())
    }

    /// Apply card transition animation
    func cardTransition() -> some View {
        self.animation(.spring(response: 0.3, dampingFraction: 0.75), value: UUID())
    }
}

// MARK: - Navigation Link with Hero Effect

struct HeroNavigationLink<Destination: View, Label: View>: View {
    let destination: Destination
    let label: Label
    @State private var isActive = false

    init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.destination = destination()
        self.label = label()
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isActive = true
            }
        }) {
            label
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            NavigationLink(
                destination: destination,
                isActive: $isActive
            ) {
                EmptyView()
            }
            .hidden()
        )
    }
}

// MARK: - Sheet Presentation Modifiers

extension View {
    /// Present sheet with smooth spring animation
    func smoothSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            content()
                .presentationBg()
                .transition(.modalPresentation)
        }
    }

    /// Present full screen cover with animation
    func smoothFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.fullScreenCover(isPresented: isPresented) {
            content()
                .transition(.heroSlide)
        }
    }
}

// MARK: - Interactive Dismissal Gesture

struct InteractiveDismissalModifier: ViewModifier {
    @Binding var isPresented: Bool
    let showHandle: Bool
    let allowExpansion: Bool
    let onExpand: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    let dismissThreshold: CGFloat = 100
    let expandThreshold: CGFloat = -80

    init(
        isPresented: Binding<Bool>,
        showHandle: Bool = true,
        allowExpansion: Bool = false,
        onExpand: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.showHandle = showHandle
        self.allowExpansion = allowExpansion
        self.onExpand = onExpand
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            // Visual handle indicator
            if showHandle {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 3)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            content
        }
        .offset(y: max(allowExpansion ? expandThreshold : 0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if allowExpansion {
            // Allow both up and down dragging
            dragOffset = value.translation.height
        } else {
            // Only allow dragging down
            if value.translation.height > 0 {
                dragOffset = value.translation.height
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        // Swipe down to dismiss
        if dragOffset > dismissThreshold {
            HapticManager.shared.swipe()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isPresented = false
            }
        }
        // Swipe up to expand (if enabled)
        else if allowExpansion && dragOffset < expandThreshold {
            HapticManager.shared.light()
            onExpand?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
            }
        }
        // Snap back
        else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = 0
            }
        }
    }
}

extension View {
    /// Add interactive dismissal gesture to sheets
    func interactiveDismissal(
        isPresented: Binding<Bool>,
        showHandle: Bool = true,
        allowExpansion: Bool = false,
        onExpand: (() -> Void)? = nil
    ) -> some View {
        self.modifier(InteractiveDismissalModifier(
            isPresented: isPresented,
            showHandle: showHandle,
            allowExpansion: allowExpansion,
            onExpand: onExpand
        ))
    }
}

// MARK: - List Item Animations

extension View {
    /// Animate list item appearance with spring
    func listItemAppearance(delay: Double = 0) -> some View {
        self
            .opacity(1)
            .offset(y: 0)
            .onAppear {
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.8)
                        .delay(delay)
                ) {
                    // Trigger animation
                }
            }
    }

    /// Scale effect on button press
    func pressAnimation() -> some View {
        self
            .scaleEffect(1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: UUID())
    }
}

// MARK: - Staggered Grid Animation

struct StaggeredGridModifier: ViewModifier {
    let index: Int
    let columns: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.8)
                        .delay(Double(index) * 0.05)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// Animate grid items with staggered delay
    func staggeredGridAnimation(index: Int, columns: Int) -> some View {
        self.modifier(StaggeredGridModifier(index: index, columns: columns))
    }
}
