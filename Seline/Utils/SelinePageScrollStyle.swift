import SwiftUI
import UIKit

struct SelinePrimaryPageScrollModifier: ViewModifier {
    let keyboardDismissMode: ScrollDismissesKeyboardMode

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(keyboardDismissMode)
            .scrollContentBackground(.hidden)
            .overlay(SelinePageScrollLockBridge().frame(width: 0, height: 0))
    }
}

private struct SelinePageScrollLockBridge: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var isAdjustingOffset = false

        func attachIfNeeded(from view: UIView) {
            guard let candidate = view.selineEnclosingScrollView else { return }

            if scrollView !== candidate {
                detach()
                scrollView = candidate
                observation = candidate.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    self?.enforceHorizontalLock(on: scrollView)
                }
            }

            configure(candidate)
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
        }

        private func configure(_ scrollView: UIScrollView) {
            scrollView.alwaysBounceHorizontal = false
            scrollView.isDirectionalLockEnabled = true
            scrollView.showsHorizontalScrollIndicator = false
            enforceHorizontalLock(on: scrollView)
        }

        private func enforceHorizontalLock(on scrollView: UIScrollView) {
            guard !isAdjustingOffset else { return }
            guard abs(scrollView.contentOffset.x) > 0.5 else { return }

            isAdjustingOffset = true
            var adjustedOffset = scrollView.contentOffset
            adjustedOffset.x = 0
            scrollView.setContentOffset(adjustedOffset, animated: false)
            isAdjustingOffset = false
        }
    }
}

private extension UIView {
    var selineEnclosingScrollView: UIScrollView? {
        var currentView = superview

        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }

        return nil
    }
}

extension View {
    func selinePrimaryPageScroll(
        keyboardDismissMode: ScrollDismissesKeyboardMode = .interactively
    ) -> some View {
        modifier(SelinePrimaryPageScrollModifier(keyboardDismissMode: keyboardDismissMode))
    }
}
