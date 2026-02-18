//
//  SwipeGestureModifiers.swift
//  Seline
//
//  Created for comprehensive swipe gesture support
//

import SwiftUI

// MARK: - SwipeAction Configuration

struct SwipeAction {
    enum ActionType {
        case delete
        case archive
        case pin
        case markRead
        case markUnread
        case complete
    }

    let type: ActionType
    let icon: String
    let color: Color
    let threshold: CGFloat
    let fullSwipeThreshold: CGFloat
    let haptic: () -> Void
    let action: () -> Void

    init(
        type: ActionType,
        icon: String,
        color: Color,
        threshold: CGFloat = 60,
        fullSwipeThreshold: CGFloat = 120,
        haptic: @escaping () -> Void,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.icon = icon
        self.color = color
        self.threshold = threshold
        self.fullSwipeThreshold = fullSwipeThreshold
        self.haptic = haptic
        self.action = action
    }
}

// MARK: - SwipeableRowModifier

struct SwipeableRowModifier: ViewModifier {
    let leftAction: SwipeAction?
    let rightAction: SwipeAction?

    @State private var offset: CGFloat = 0
    @State private var hasPlayedThresholdHaptic = false
    @State private var hasPlayedFullSwipeHaptic = false
    @State private var isExecuting = false
    @State private var activeAxis: DragAxis? = nil

    private enum DragAxis {
        case horizontal
        case vertical
    }

    private var animation: Animation {
        .spring(response: 0.3, dampingFraction: 0.75)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            // Background color and icon
            if offset != 0 {
                actionBackground
            }

            // Main content with offset
            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            handleDragChangedWithAxisLock(value)
                        }
                        .onEnded { value in
                            handleDragEndedWithAxisLock(value)
                        }
                )
        }
    }

    // MARK: - Background View

    private var actionBackground: some View {
        GeometryReader { geometry in
            HStack {
                if offset > 0, let action = rightAction {
                    // Right swipe action (left side)
                    actionView(action, dragAmount: offset)
                        .frame(maxWidth: min(offset, geometry.size.width))
                    Spacer()
                } else if offset < 0, let action = leftAction {
                    // Left swipe action (right side)
                    Spacer()
                    actionView(action, dragAmount: abs(offset))
                        .frame(maxWidth: min(abs(offset), geometry.size.width))
                }
            }
            .background(
                (offset > 0 ? rightAction?.color : leftAction?.color)?
                    .opacity(min(abs(offset) / 100.0, 1.0))
            )
        }
    }

    private func actionView(_ action: SwipeAction, dragAmount: CGFloat) -> some View {
        let scale = min(max(dragAmount / action.threshold, 0.6), 1.0)
        let opacity = min(dragAmount / action.threshold, 1.0)

        return Image(systemName: action.icon)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.white)
            .scaleEffect(scale)
            .opacity(opacity)
            .padding(.horizontal, 20)
    }

    // MARK: - Gesture Handlers

    private func handleDragChangedWithAxisLock(_ value: DragGesture.Value) {
        guard !isExecuting else { return }

        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)

        if activeAxis == nil {
            // Prefer vertical scroll unless the user makes a deliberate horizontal swipe.
            if horizontalMovement > 14 && horizontalMovement > verticalMovement * 2.2 {
                activeAxis = .horizontal
            } else if verticalMovement > 8 && verticalMovement > horizontalMovement * 1.05 {
                activeAxis = .vertical
                return
            } else {
                return
            }
        }

        guard activeAxis == .horizontal else { return }
        handleDragChanged(value)
    }

    private func handleDragEndedWithAxisLock(_ value: DragGesture.Value) {
        defer { activeAxis = nil }

        guard activeAxis == .horizontal else {
            if offset != 0 {
                resetState()
            }
            return
        }

        handleDragEnded(value)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !isExecuting else { return }

        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)

        // Only activate if horizontal movement is >2x vertical (avoid conflict with scrolling)
        guard horizontalMovement > verticalMovement * 2 else { return }

        let newOffset = value.translation.width

        // Check if action exists for this direction
        if newOffset > 0 && rightAction == nil { return }
        if newOffset < 0 && leftAction == nil { return }

        offset = newOffset

        // Threshold haptic feedback
        let currentAction = newOffset > 0 ? rightAction : leftAction
        if let action = currentAction {
            if abs(newOffset) >= action.threshold && !hasPlayedThresholdHaptic {
                action.haptic()
                hasPlayedThresholdHaptic = true
            }

            // Full swipe haptic
            if abs(newOffset) >= action.fullSwipeThreshold && !hasPlayedFullSwipeHaptic {
                HapticManager.shared.light()
                hasPlayedFullSwipeHaptic = true
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard !isExecuting else { return }

        let horizontalMovement = abs(value.translation.width)
        let verticalMovement = abs(value.translation.height)

        // Verify this was a horizontal gesture
        guard horizontalMovement > verticalMovement * 2 else {
            resetState()
            return
        }

        let finalOffset = value.translation.width
        let currentAction = finalOffset > 0 ? rightAction : leftAction

        guard let action = currentAction else {
            resetState()
            return
        }

        // Full swipe - auto execute
        if abs(finalOffset) >= action.fullSwipeThreshold {
            executeAction(action)
        }
        // Threshold reached - execute on release
        else if abs(finalOffset) >= action.threshold {
            executeAction(action)
        }
        // Below threshold - snap back
        else {
            resetState()
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: SwipeAction) {
        isExecuting = true

        withAnimation(animation) {
            // Slide out further to indicate execution
            offset = offset > 0 ? 400 : -400
        }

        // Execute action after brief animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            action.action()

            // Reset after action completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                resetState()
            }
        }
    }

    private func resetState() {
        withAnimation(animation) {
            offset = 0
        }
        hasPlayedThresholdHaptic = false
        hasPlayedFullSwipeHaptic = false
        isExecuting = false
    }
}

// MARK: - View Extension

extension View {
    func swipeActions(
        left: SwipeAction? = nil,
        right: SwipeAction? = nil
    ) -> some View {
        self.modifier(SwipeableRowModifier(
            leftAction: left,
            rightAction: right
        ))
    }
}
