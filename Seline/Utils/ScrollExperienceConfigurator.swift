import UIKit

/// Intentionally left as a no-op so scrolling stays on iOS native behavior.
enum ScrollExperienceConfigurator {
    static func installGlobalAppearance() {}

    @MainActor
    static func applyToVisibleScrollViews() {}
}
