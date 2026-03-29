import SwiftUI
import UIKit

struct InteractiveSidebarOverlay<MainContent: View, SidebarContent: View>: View {
    private enum CloseDragAxis: Equatable {
        case horizontal
        case vertical
    }

    @Binding var isPresented: Bool
    let canOpen: Bool
    let sidebarWidth: CGFloat
    let colorScheme: ColorScheme
    let showsTrailingDivider: Bool
    let mainContent: () -> MainContent
    let sidebarContent: () -> SidebarContent
    @State private var dragOffset: CGFloat = 0
    @State private var closeDragAxis: CloseDragAxis?
    @State private var suppressSidebarContentTouches = false

    init(
        isPresented: Binding<Bool>,
        canOpen: Bool = true,
        sidebarWidth: CGFloat,
        colorScheme: ColorScheme,
        showsTrailingDivider: Bool = true,
        @ViewBuilder mainContent: @escaping () -> MainContent,
        @ViewBuilder sidebarContent: @escaping () -> SidebarContent
    ) {
        self._isPresented = isPresented
        self.canOpen = canOpen
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        self.showsTrailingDivider = showsTrailingDivider
        self.mainContent = mainContent
        self.sidebarContent = sidebarContent
    }

    private var spring: Animation {
        .interactiveSpring(response: 0.32, dampingFraction: 0.92, blendDuration: 0.18)
    }

    private var shouldRenderOverlay: Bool {
        isPresented || dragOffset != 0
    }

    /// How far the sidebar has slid into view (0 = fully hidden, sidebarWidth = fully open).
    private var currentSlide: CGFloat {
        if isPresented {
            // Fully open, but allow drag to pull it closed (negative drag).
            return max(0, sidebarWidth + dragOffset)
        }
        // Closed, but allow drag to pull it open (positive drag).
        return max(0, dragOffset)
    }

    private var openProgress: CGFloat {
        min(1, max(0, currentSlide / sidebarWidth))
    }

    private func resetCloseDragTracking() {
        closeDragAxis = nil
        suppressSidebarContentTouches = false
    }

    private func dismissSidebar() {
        withAnimation(spring) {
            isPresented = false
            dragOffset = 0
        }
    }

    private var sidebarCloseDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard isPresented else { return }

                let horizontal = value.translation.width
                let horizontalMagnitude = abs(horizontal)
                let verticalMagnitude = abs(value.translation.height)

                if closeDragAxis == nil {
                    if horizontal < 0,
                       horizontalMagnitude > 14,
                       horizontalMagnitude > verticalMagnitude * 2.2 {
                        closeDragAxis = .horizontal
                        suppressSidebarContentTouches = true
                    } else if verticalMagnitude > 8,
                              verticalMagnitude > horizontalMagnitude * 1.05 {
                        closeDragAxis = .vertical
                        return
                    } else {
                        return
                    }
                }

                guard closeDragAxis == .horizontal else { return }
                guard horizontal < 0 else {
                    dragOffset = 0
                    return
                }

                dragOffset = max(horizontal, -sidebarWidth)
            }
            .onEnded { value in
                defer { resetCloseDragTracking() }

                guard isPresented else {
                    dragOffset = 0
                    return
                }

                guard closeDragAxis == .horizontal else {
                    withAnimation(spring) {
                        dragOffset = 0
                    }
                    return
                }

                let projected = min(value.translation.width, value.predictedEndTranslation.width)
                let shouldClose = projected < -sidebarWidth * 0.35

                withAnimation(spring) {
                    isPresented = !shouldClose
                    dragOffset = 0
                }
            }
    }

    private func postSidebarVisibility(_ isVisible: Bool) {
        NotificationCenter.default.post(
            name: .interactiveSidebarVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": isVisible]
        )
    }

    var body: some View {
        GeometryReader { _ in
            let mainOffset = currentSlide  // 0 when closed, sidebarWidth when fully open

            ZStack(alignment: .leading) {
                // Sidebar panel — positioned at the left, slides in via offset
                if shouldRenderOverlay {
                    HStack(spacing: 0) {
                        sidebarContent()
                            .allowsHitTesting(!suppressSidebarContentTouches)
                            .frame(width: sidebarWidth)
                            .background(colorScheme == .dark ? Color.black : .white)
                            .overlay(alignment: .trailing) {
                                if showsTrailingDivider {
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                                        .frame(width: 1)
                                }
                            }

                        Spacer(minLength: 0)
                    }
                    .offset(x: currentSlide - sidebarWidth) // -sidebarWidth (hidden) → 0 (visible)
                }

                // Main content panel — pushes right 1:1 with sidebar
                ZStack {
                    mainContent()
                        .allowsHitTesting(!shouldRenderOverlay)

                    if shouldRenderOverlay {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissSidebar()
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .offset(x: mainOffset)
                .simultaneousGesture(sidebarCloseDragGesture)
                .animation(spring, value: isPresented)

                // Edge pan gesture catcher (always at the screen's left edge)
                if canOpen && !isPresented {
                    NativeEdgePanCapture(
                        edgeActivationWidth: 26,
                        onChanged: { translationX, _ in
                            guard canOpen, !isPresented else { return }
                            let horizontal = max(0, translationX)
                            dragOffset = min(horizontal, sidebarWidth)
                        },
                        onEnded: { translationX, velocityX in
                            guard canOpen, !isPresented else {
                                dragOffset = 0
                                return
                            }

                            let projected = max(translationX + (velocityX * 0.18), translationX)
                            let shouldOpen = projected > sidebarWidth * 0.35

                            withAnimation(spring) {
                                isPresented = shouldOpen
                                dragOffset = 0
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            postSidebarVisibility(shouldRenderOverlay)
        }
        .onChange(of: shouldRenderOverlay) { isVisible in
            postSidebarVisibility(isVisible)
        }
        .onChange(of: isPresented) { isVisible in
            if !isVisible {
                dragOffset = 0
                resetCloseDragTracking()
            }
        }
        .onDisappear {
            dragOffset = 0
            resetCloseDragTracking()
            postSidebarVisibility(false)
        }
    }
}

extension Notification.Name {
    static let interactiveSidebarVisibilityChanged = Notification.Name("interactiveSidebarVisibilityChanged")
}

private struct NativeEdgePanCapture: UIViewRepresentable {
    let edgeActivationWidth: CGFloat
    let onChanged: (CGFloat, CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = EdgePassthroughView()
        view.edgeActivationWidth = edgeActivationWidth
        view.backgroundColor = .clear

        let pan = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.edges = .left
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let edgeView = uiView as? EdgePassthroughView {
            edgeView.edgeActivationWidth = edgeActivationWidth
        }
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat, CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void

        init(
            onChanged: @escaping (CGFloat, CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            let translationX = gesture.translation(in: gesture.view).x
            let velocityX = gesture.velocity(in: gesture.view).x

            switch gesture.state {
            case .began, .changed:
                onChanged(translationX, velocityX)
            case .ended, .cancelled, .failed:
                onEnded(translationX, velocityX)
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    final class EdgePassthroughView: UIView {
        var edgeActivationWidth: CGFloat = 26

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            point.x <= edgeActivationWidth
        }
    }
}
