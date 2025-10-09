import UIKit
import SwiftUI

/// Centralized haptic feedback manager with different patterns for different app components
class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // MARK: - Component-Specific Haptics

    /// Light tap for buttons and general interactions
    func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Medium impact for important actions
    func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Heavy impact for critical actions
    func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    /// Soft feedback for subtle interactions
    func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    /// Rigid feedback for firm interactions
    func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }

    // MARK: - Notification Haptics

    /// Success feedback (like saving, completing tasks)
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Warning feedback (like validation errors)
    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Error feedback (like failed operations)
    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Selection Haptics

    /// Selection change feedback (like scrolling through items)
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // MARK: - Custom Pattern Haptics

    /// Button tap - light and quick
    func buttonTap() {
        light()
    }

    /// Navigation - medium feedback for moving between screens
    func navigation() {
        medium()
    }

    /// Delete action - double heavy impact
    func delete() {
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.heavy()
        }
    }

    /// Toggle switch - soft click
    func toggle() {
        soft()
    }

    /// Pin/Unpin - rigid feedback
    func pin() {
        rigid()
    }

    /// Save action - success with light impact
    func save() {
        success()
    }

    /// Card tap - light feedback
    func cardTap() {
        light()
    }

    /// Long press - medium then light
    func longPress() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.light()
        }
    }

    /// Swipe action - selection feedback
    func swipe() {
        selection()
    }

    /// Pull to refresh - soft feedback
    func pullRefresh() {
        soft()
    }

    /// Text input focus - light tap
    func textFocus() {
        light()
    }

    /// Lock/Unlock - heavy impact
    func lockToggle() {
        heavy()
    }

    /// AI action start - medium + light pattern
    func aiActionStart() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.light()
        }
    }

    /// AI action complete - success pattern
    func aiActionComplete() {
        success()
    }

    /// Sheet present/dismiss - soft feedback
    func sheet() {
        soft()
    }

    /// Tab change - selection feedback
    func tabChange() {
        selection()
    }

    /// Folder action - medium feedback
    func folder() {
        medium()
    }

    /// Email action - light feedback
    func email() {
        light()
    }

    /// Calendar/Event action - soft feedback
    func calendar() {
        soft()
    }

    /// Map interaction - light feedback
    func map() {
        light()
    }

    /// Search - selection feedback
    func search() {
        selection()
    }

    /// Filter applied - rigid feedback
    func filter() {
        rigid()
    }

    /// Image attachment - light feedback
    func imageAttachment() {
        light()
    }

    /// Voice input - medium feedback
    func voiceInput() {
        medium()
    }
}

// MARK: - SwiftUI View Extension for easy haptic access

extension View {
    /// Add haptic feedback to any view
    func hapticFeedback(_ haptic: @escaping () -> Void, trigger: some Equatable) -> some View {
        self.onChange(of: trigger) { _ in
            haptic()
        }
    }
}
