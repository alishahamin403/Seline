import SwiftUI

// MARK: - Haptic Feedback View Modifiers
// Easy-to-use modifiers for adding haptic feedback throughout the app

extension View {
    /// Add light haptic feedback on tap
    func hapticTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.lightTap()
            }
        )
    }

    /// Add button tap haptic feedback
    func hapticButton() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.buttonTap()
            }
        )
    }

    /// Add card tap haptic feedback
    func hapticCard() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.cardTap()
            }
        )
    }

    /// Add selection change haptic (for filters, pickers)
    func hapticSelection() -> some View {
        self.onChange(of: UUID()) { _ in
            HapticManager.shared.selection()
        }
    }

    /// Add navigation haptic feedback
    func hapticNavigation() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.navigation()
            }
        )
    }

    /// Add toggle haptic feedback
    func hapticToggle<T: Equatable>(value: T) -> some View {
        self.onChange(of: value) { _ in
            HapticManager.shared.toggle()
        }
    }

    /// Add save action haptic
    func hapticSave() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.save()
            }
        )
    }

    /// Add delete action haptic
    func hapticDelete() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticManager.shared.delete()
            }
        )
    }

    /// Add swipe interaction haptic
    func hapticSwipe() -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { _ in
                    HapticManager.shared.swipeInteraction()
                }
        )
    }
}

// MARK: - Button Style with Haptic Feedback

struct HapticButtonStyle: ButtonStyle {
    let hapticType: HapticType

    enum HapticType {
        case light, medium, heavy, success, navigation, card

        func trigger() {
            switch self {
            case .light:
                HapticManager.shared.lightTap()
            case .medium:
                HapticManager.shared.medium()
            case .heavy:
                HapticManager.shared.heavy()
            case .success:
                HapticManager.shared.success()
            case .navigation:
                HapticManager.shared.navigation()
            case .card:
                HapticManager.shared.cardTap()
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    hapticType.trigger()
                }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    /// Button style with light haptic feedback
    static var hapticLight: HapticButtonStyle {
        HapticButtonStyle(hapticType: .light)
    }

    /// Button style with card haptic feedback
    static var hapticCard: HapticButtonStyle {
        HapticButtonStyle(hapticType: .card)
    }

    /// Button style with navigation haptic feedback
    static var hapticNavigation: HapticButtonStyle {
        HapticButtonStyle(hapticType: .navigation)
    }

    /// Button style with success haptic feedback
    static var hapticSuccess: HapticButtonStyle {
        HapticButtonStyle(hapticType: .success)
    }
}

// MARK: - Picker with Haptic Feedback

struct HapticPicker<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    let content: Content

    init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(selection: Binding(
            get: { selection },
            set: { newValue in
                HapticManager.shared.selection()
                selection = newValue
            }
        ), label: EmptyView()) {
            content
        }
    }
}

// MARK: - Toggle with Haptic Feedback

struct HapticToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                HapticManager.shared.toggle()
                isOn = newValue
            }
        )) {
            Text(label)
        }
    }
}

// MARK: - Slider with Haptic Feedback

struct HapticSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    @State private var lastHapticValue: Double = 0

    var body: some View {
        Slider(value: Binding(
            get: { value },
            set: { newValue in
                // Trigger haptic every 10% change
                let diff = abs(newValue - lastHapticValue)
                if diff >= (bounds.upperBound - bounds.lowerBound) * 0.1 {
                    HapticManager.shared.selection()
                    lastHapticValue = newValue
                }
                value = newValue
            }
        ), in: bounds)
    }
}

// MARK: - Haptic Pull-to-Refresh

extension View {
    /// Add haptic feedback to refreshable views
    func hapticRefreshable(action: @escaping () async -> Void) -> some View {
        self.refreshable {
            HapticManager.shared.pullRefresh()
            await action()
        }
    }
}

// MARK: - Context Menu with Haptics

extension View {
    /// Add context menu with haptic feedback
    func hapticContextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        self.contextMenu {
            menuItems()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    HapticManager.shared.longPress()
                }
        )
    }
}
