import SwiftUI

// MARK: - Reorderable Widget Container

struct ReorderableWidgetContainer<Content: View>: View {
    @ObservedObject var widgetManager: WidgetManager
    let widgetType: HomeWidgetType
    let content: () -> Content
    @Environment(\.colorScheme) var colorScheme

    init(
        widgetManager: WidgetManager,
        type: HomeWidgetType,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.widgetManager = widgetManager
        self.widgetType = type
        self.content = content
    }
    
    var body: some View {
        Group {
            if widgetManager.isEditMode {
                // Edit mode: allow drag gestures for reordering
                editModeView
            } else {
                // Normal mode: no gesture interference, let ScrollView handle everything
                normalModeView
                    .onLongPressGesture(minimumDuration: 0.5) {
                        widgetManager.enterEditMode()
                    }
            }
        }
    }
    
    private var normalModeView: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .scaleEffect(1.0)
                .opacity(1.0)
            
            // No overlay, no gestures in normal mode - completely transparent to ScrollView
        }
        .offset(.zero)
        .zIndex(0)
    }
    
    private var editModeView: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .scaleEffect(0.95)
                .allowsHitTesting(false) // Disable clicks on widget content in edit mode
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2),
                            lineWidth: 2
                        )
                )

            // Control buttons (up, down, remove)
            HStack(spacing: 8) {
                // Move up button
                Button(action: {
                    moveWidgetUp()
                }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.black : Color.white)
                                .frame(width: 20, height: 20)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(canMoveUp() ? 1.0 : 0.3)
                .disabled(!canMoveUp())

                // Move down button
                Button(action: {
                    moveWidgetDown()
                }) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.black : Color.white)
                                .frame(width: 20, height: 20)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(canMoveDown() ? 1.0 : 0.3)
                .disabled(!canMoveDown())

                // Remove button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        widgetManager.hideWidget(widgetType)
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.black : Color.white)
                                .frame(width: 20, height: 20)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .offset(x: 8, y: -8)
            .transition(.scale.combined(with: .opacity))
        }
        .rotationEffect(
            Angle(degrees: Double.random(in: -1...1))
        )
        .animation(
            Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true),
            value: widgetManager.isEditMode
        )
    }

    // MARK: - Helper Methods

    private func canMoveUp() -> Bool {
        let visibleWidgets = widgetManager.visibleWidgets
        guard let currentIndex = visibleWidgets.firstIndex(where: { $0.type == widgetType }) else {
            return false
        }
        return currentIndex > 0
    }

    private func canMoveDown() -> Bool {
        let visibleWidgets = widgetManager.visibleWidgets
        guard let currentIndex = visibleWidgets.firstIndex(where: { $0.type == widgetType }) else {
            return false
        }
        return currentIndex < visibleWidgets.count - 1
    }

    private func moveWidgetUp() {
        let visibleWidgets = widgetManager.visibleWidgets
        guard let currentIndex = visibleWidgets.firstIndex(where: { $0.type == widgetType }),
              currentIndex > 0 else {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            widgetManager.moveWidget(widgetType, toIndex: currentIndex - 1)
        }
        HapticManager.shared.selection()
    }

    private func moveWidgetDown() {
        let visibleWidgets = widgetManager.visibleWidgets
        guard let currentIndex = visibleWidgets.firstIndex(where: { $0.type == widgetType }),
              currentIndex < visibleWidgets.count - 1 else {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            widgetManager.moveWidget(widgetType, toIndex: currentIndex + 1)
        }
        HapticManager.shared.selection()
    }
}

// MARK: - Add Widget Button

struct AddWidgetButton: View {
    @ObservedObject var widgetManager: WidgetManager
    let widgetType: HomeWidgetType
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                widgetManager.showWidget(widgetType)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: widgetType.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 24)

                Text(widgetType.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Widget Edit Mode Overlay

struct WidgetEditModeOverlay: View {
    @ObservedObject var widgetManager: WidgetManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showAddWidgets = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact top bar
            HStack(spacing: 12) {
                // Edit mode indicator
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    Text("Edit Mode")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                Spacer()

                // Add Widget Button (only show if there are hidden widgets)
                if !widgetManager.hiddenWidgets.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showAddWidgets.toggle()
                        }
                        HapticManager.shared.selection()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)

                            Text("Add")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Done button
                Button("Done") {
                    widgetManager.exitEditMode()
                    showAddWidgets = false
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Hidden widgets section (dropdown from top bar)
            if showAddWidgets && !widgetManager.hiddenWidgets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Widgets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        ForEach(widgetManager.hiddenWidgets) { config in
                            AddWidgetButton(widgetManager: widgetManager, widgetType: config.type)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ReorderableWidgetContainer(
            widgetManager: WidgetManager.shared,
            type: .dailyOverview
        ) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.3))
                .frame(height: 120)
                .overlay(Text("Daily Overview Widget"))
        }
        .padding()
    }
}

