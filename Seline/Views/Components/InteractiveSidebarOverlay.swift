import SwiftUI
import UIKit

struct InteractiveSidebarOverlay<MainContent: View, SidebarContent: View>: View {
    private enum DragAxis: Equatable {
        case horizontal
        case vertical
    }

    @Binding var isPresented: Bool
    let canOpen: Bool
    let allowsInteractiveDrag: Bool
    let sidebarWidth: CGFloat
    let colorScheme: ColorScheme
    let onOverlayVisibilityChanged: ((Bool) -> Void)?
    let mainContent: MainContent
    let sidebarContent: SidebarContent
    @State private var dragOffset: CGFloat = 0
    @State private var closeDragAxis: DragAxis?
    @State private var openDragAxis: DragAxis?
    @State private var suppressSidebarContentTouches = false

    init(
        isPresented: Binding<Bool>,
        canOpen: Bool = true,
        allowsInteractiveDrag: Bool = true,
        sidebarWidth: CGFloat,
        colorScheme: ColorScheme,
        onOverlayVisibilityChanged: ((Bool) -> Void)? = nil,
        @ViewBuilder mainContent: @escaping () -> MainContent,
        @ViewBuilder sidebarContent: @escaping () -> SidebarContent
    ) {
        self._isPresented = isPresented
        self.canOpen = canOpen
        self.allowsInteractiveDrag = allowsInteractiveDrag
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        self.onOverlayVisibilityChanged = onOverlayVisibilityChanged
        self.mainContent = mainContent()
        self.sidebarContent = sidebarContent()
    }

    private var spring: Animation {
        .interactiveSpring(response: 0.32, dampingFraction: 0.92, blendDuration: 0.18)
    }

    private var shouldRenderOverlay: Bool {
        isPresented || dragOffset != 0
    }

    private var shouldKeepSidebarMounted: Bool {
        canOpen || shouldRenderOverlay
    }

    private var shouldEnableInteractiveDrag: Bool {
        allowsInteractiveDrag && canOpen
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

    private var mainContentScrimOpacity: Double {
        let maxOpacity: Double = colorScheme == .dark ? 0.26 : 0.12
        return maxOpacity * Double(openProgress)
    }

    private var mainContentScrimColor: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.18)
            : .black
    }

    private func resetCloseDragTracking() {
        closeDragAxis = nil
        suppressSidebarContentTouches = false
    }

    private func resetOpenDragTracking() {
        openDragAxis = nil
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

    private func publishOverlayVisibility(_ isVisible: Bool) {
        onOverlayVisibilityChanged?(isVisible)
    }

    @ViewBuilder
    private func overlayBody(mainOffset: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Sidebar panel — positioned at the left, slides in via offset
            if shouldKeepSidebarMounted {
                HStack(spacing: 0) {
                    ZStack(alignment: .trailing) {
                        (colorScheme == .dark ? Color.black : Color.white)

                        sidebarContent
                            .allowsHitTesting(!suppressSidebarContentTouches)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .frame(width: sidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .offset(x: currentSlide - sidebarWidth) // -sidebarWidth (hidden) → 0 (visible)
            }

            // Main content panel — pushes right 1:1 with sidebar
            mainContent
                .allowsHitTesting(!shouldRenderOverlay)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .offset(x: mainOffset)

            // Scrim overlay — sits OUTSIDE clipped content so it covers safe areas too
            if shouldRenderOverlay {
                mainContentScrimColor
                    .opacity(mainContentScrimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissSidebar()
                    }
                    .offset(x: mainOffset)
            }

            // Edge pan gesture catcher (always at the screen's left edge)
            if shouldEnableInteractiveDrag && !isPresented {
                NativeEdgePanCapture(
                    edgeActivationWidth: 26,
                    onChanged: { translation, velocity in
                        guard canOpen, !isPresented else { return }
                        let horizontal = max(0, translation.x)
                        let verticalMagnitude = abs(translation.y)

                        if openDragAxis == nil {
                            if horizontal > 14,
                               horizontal > verticalMagnitude * 1.35 {
                                openDragAxis = .horizontal
                            } else if verticalMagnitude > 8,
                                      verticalMagnitude > max(1, horizontal) * 1.05 {
                                openDragAxis = .vertical
                                return
                            } else {
                                return
                            }
                        }

                        guard openDragAxis == .horizontal else { return }

                        // Ignore ambiguous swipes and only start shifting the page
                        // once the edge gesture is clearly horizontal.
                        let projectedHorizontal = max(horizontal, horizontal + max(0, velocity.x) * 0.02)
                        dragOffset = min(projectedHorizontal, sidebarWidth)
                    },
                    onEnded: { translation, velocity in
                        defer { resetOpenDragTracking() }

                        guard canOpen, !isPresented else {
                            dragOffset = 0
                            return
                        }

                        guard openDragAxis == .horizontal else {
                            withAnimation(spring) {
                                dragOffset = 0
                            }
                            return
                        }

                        let projected = max(translation.x + (velocity.x * 0.18), translation.x)
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

    var body: some View {
        GeometryReader { _ in
            let mainOffset = currentSlide  // 0 when closed, sidebarWidth when fully open
            overlayBody(mainOffset: mainOffset)
                .simultaneousGesture(
                    sidebarCloseDragGesture,
                    including: isPresented && allowsInteractiveDrag ? .all : .none
                )
        }
        .onAppear {
            publishOverlayVisibility(shouldRenderOverlay)
        }
        .onChange(of: shouldRenderOverlay) { isVisible in
            publishOverlayVisibility(isVisible)
        }
        .onChange(of: isPresented) { isVisible in
            if !isVisible {
                dragOffset = 0
                resetCloseDragTracking()
                resetOpenDragTracking()
            }
        }
        .onDisappear {
            dragOffset = 0
            resetCloseDragTracking()
            resetOpenDragTracking()
            publishOverlayVisibility(false)
        }
    }
}

private struct NativeEdgePanCapture: UIViewRepresentable {
    let edgeActivationWidth: CGFloat
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint, CGPoint) -> Void

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
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void

        init(
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)

            switch gesture.state {
            case .began, .changed:
                onChanged(translation, velocity)
            case .ended, .cancelled, .failed:
                onEnded(translation, velocity)
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
