import SwiftUI
import UIKit

struct InteractiveSidebarOverlay<SidebarContent: View>: View {
    @Binding var isPresented: Bool
    let canOpen: Bool
    let sidebarWidth: CGFloat
    let colorScheme: ColorScheme
    let showsTrailingDivider: Bool
    let sidebarContent: () -> SidebarContent
    @State private var dragOffset: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        canOpen: Bool = true,
        sidebarWidth: CGFloat,
        colorScheme: ColorScheme,
        showsTrailingDivider: Bool = true,
        @ViewBuilder sidebarContent: @escaping () -> SidebarContent
    ) {
        self._isPresented = isPresented
        self.canOpen = canOpen
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        self.showsTrailingDivider = showsTrailingDivider
        self.sidebarContent = sidebarContent
    }

    private var spring: Animation {
        .interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.18)
    }

    private var shouldRenderOverlay: Bool {
        isPresented || dragOffset != 0
    }

    private var currentSidebarOffset: CGFloat {
        if isPresented {
            return min(0, dragOffset)
        }
        return -sidebarWidth + max(0, dragOffset)
    }

    private var openProgress: CGFloat {
        let progress = 1 + (currentSidebarOffset / sidebarWidth)
        return min(1, max(0, progress))
    }

    private var sidebarCloseDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard isPresented else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal < 0, abs(horizontal) > vertical else { return }

                dragOffset = max(horizontal, -sidebarWidth)
            }
            .onEnded { value in
                guard isPresented else {
                    dragOffset = 0
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
        ZStack(alignment: .leading) {
            if shouldRenderOverlay {
                Color.black
                    .opacity(0.3 * openProgress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(spring) {
                            isPresented = false
                        }
                    }

                HStack(spacing: 0) {
                    sidebarContent()
                        .frame(width: sidebarWidth)
                        .background(colorScheme == .dark ? Color.black : .white)
                        .overlay(alignment: .trailing) {
                            if showsTrailingDivider {
                                Rectangle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                                    .frame(width: 1)
                            }
                        }
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.28 : 0.1),
                            radius: 14,
                            x: 2,
                            y: 0
                        )
                        .offset(x: currentSidebarOffset)
                        .simultaneousGesture(sidebarCloseDragGesture)

                    Spacer(minLength: 0)
                }

                if isPresented {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: sidebarWidth)
                            .allowsHitTesting(false)

                        NativeSidebarClosePanCapture(
                            sidebarWidth: sidebarWidth,
                            onChanged: { translationX in
                                let horizontal = min(translationX, 0)
                                dragOffset = max(horizontal, -sidebarWidth)
                            },
                            onEnded: { translationX, velocityX in
                                let projected = min(translationX + (velocityX * 0.18), translationX)
                                let shouldClose = projected < -sidebarWidth * 0.35

                                withAnimation(spring) {
                                    isPresented = !shouldClose
                                    dragOffset = 0
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }

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

                        // Projected position gives a more native "follow finger + momentum" feel.
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
        .onAppear {
            postSidebarVisibility(isPresented)
        }
        .onChange(of: isPresented) { isVisible in
            postSidebarVisibility(isVisible)
        }
        .onDisappear {
            postSidebarVisibility(false)
        }
    }
}

extension Notification.Name {
    static let interactiveSidebarVisibilityChanged = Notification.Name("interactiveSidebarVisibilityChanged")
}

private struct NativeSidebarClosePanCapture: UIViewRepresentable {
    let sidebarWidth: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        context.coordinator.sidebarWidth = sidebarWidth
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.sidebarWidth = sidebarWidth
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarWidth: sidebarWidth,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var sidebarWidth: CGFloat
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void

        init(
            sidebarWidth: CGFloat,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.sidebarWidth = sidebarWidth
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translationX = gesture.translation(in: gesture.view).x
            let velocity = gesture.velocity(in: gesture.view)

            switch gesture.state {
            case .began, .changed:
                if translationX <= 0 {
                    onChanged(translationX)
                }
            case .ended, .cancelled, .failed:
                onEnded(translationX, velocity.x)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
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
            // Favor edge pan for opening sidebar; avoids scroll gesture conflicts.
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
