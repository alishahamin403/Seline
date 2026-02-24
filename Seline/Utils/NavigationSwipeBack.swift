import SwiftUI
import UIKit
import ObjectiveC.runtime

enum NavigationSwipeBack {
    private static var didInstall = false

    static func installGlobalSupport() {
        guard !didInstall else { return }
        didInstall = true
        UINavigationController.selineInstallInteractivePopSupport()
    }
}

private extension UINavigationController {
    static func selineInstallInteractivePopSupport() {
        selineSwizzle(
            original: #selector(UINavigationController.viewDidLoad),
            swizzled: #selector(UINavigationController.selineViewDidLoad)
        )
        selineSwizzle(
            original: #selector(UINavigationController.viewDidAppear(_:)),
            swizzled: #selector(UINavigationController.selineViewDidAppear(_:))
        )
        selineSwizzle(
            original: #selector(UINavigationController.pushViewController(_:animated:)),
            swizzled: #selector(UINavigationController.selinePushViewController(_:animated:))
        )
    }

    static func selineSwizzle(original: Selector, swizzled: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(self, original),
            let swizzledMethod = class_getInstanceMethod(self, swizzled)
        else {
            return
        }

        // Safe swizzle pattern:
        // If `original` is inherited (e.g. from UIViewController), first add an override on this class.
        // This avoids mutating superclass method implementations and crashing non-navigation controllers.
        let didAddMethod = class_addMethod(
            self,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAddMethod {
            class_replaceMethod(
                self,
                swizzled,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    @objc func selineViewDidLoad() {
        selineViewDidLoad()
        selineConfigureInteractivePopGesture()
    }

    @objc func selineViewDidAppear(_ animated: Bool) {
        selineViewDidAppear(animated)
        selineConfigureInteractivePopGesture()
    }

    @objc func selinePushViewController(_ viewController: UIViewController, animated: Bool) {
        selinePushViewController(viewController, animated: animated)
        selineConfigureInteractivePopGesture()
    }

    func selineConfigureInteractivePopGesture() {
        guard let popGesture = interactivePopGestureRecognizer else { return }
        popGesture.isEnabled = true
        popGesture.delegate = nil
        popGesture.cancelsTouchesInView = false
    }
}

private struct EdgeSwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var isTrackingFromEdge = false
    @State private var hasTriggeredDismiss = false
    @State private var dragX: CGFloat = 0
    @State private var isAnimatingOffscreen = false

    private let edgeWidth: CGFloat = 28
    private let triggerDistance: CGFloat = 90
    private let maxVerticalTravel: CGFloat = 90

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .offset(x: currentOffsetX)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { value in
                        guard !isAnimatingOffscreen else { return }
                        guard !hasTriggeredDismiss else { return }

                        if !isTrackingFromEdge {
                            guard value.startLocation.x <= edgeWidth else { return }
                            guard value.translation.width > 0 else { return }
                            isTrackingFromEdge = true
                        }

                        guard isTrackingFromEdge else { return }

                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)

                        guard horizontal > vertical else { return }
                        dragX = max(0, horizontal)

                        guard horizontal >= triggerDistance else { return }
                        guard vertical <= maxVerticalTravel else { return }

                        hasTriggeredDismiss = true
                        HapticManager.shared.light()
                        withAnimation(.easeOut(duration: 0.18)) {
                            isAnimatingOffscreen = true
                            dragX = UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            dismiss()
                            resetGestureState()
                        }
                    }
                    .onEnded { _ in
                        guard !isAnimatingOffscreen else { return }
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                            dragX = 0
                        }
                        isTrackingFromEdge = false
                        hasTriggeredDismiss = false
                    }
            )
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: dragX)
    }

    private var currentOffsetX: CGFloat {
        isAnimatingOffscreen ? UIScreen.main.bounds.width : dragX
    }

    private func resetGestureState() {
        isTrackingFromEdge = false
        hasTriggeredDismiss = false
        dragX = 0
        isAnimatingOffscreen = false
    }
}

extension View {
    func edgeSwipeBackEnabled() -> some View {
        modifier(EdgeSwipeBackModifier())
    }
}
