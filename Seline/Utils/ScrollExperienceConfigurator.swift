import UIKit

/// Centralized scroll tuning to keep drag + momentum behavior consistent across screens.
enum ScrollExperienceConfigurator {
    private static var hasInstalledGlobalAppearance = false

    static func installGlobalAppearance() {
        guard !hasInstalledGlobalAppearance else { return }
        hasInstalledGlobalAppearance = true

        let scrollAppearance = UIScrollView.appearance()
        scrollAppearance.delaysContentTouches = true
        scrollAppearance.canCancelContentTouches = true
        scrollAppearance.keyboardDismissMode = .interactive
        scrollAppearance.decelerationRate = .normal
    }

    @MainActor
    static func applyToVisibleScrollViews() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            let keyWindow = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            if let keyWindow {
                configureScrollViews(in: keyWindow)
            }
        }
    }

    @MainActor
    private static func configureScrollViews(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.delaysContentTouches = true
            scrollView.canCancelContentTouches = true
            scrollView.keyboardDismissMode = .interactive
            scrollView.decelerationRate = .normal
        }

        for subview in view.subviews {
            configureScrollViews(in: subview)
        }
    }
}
