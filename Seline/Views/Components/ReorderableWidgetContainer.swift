import SwiftUI

// MARK: - Reorderable Widget Container

struct ReorderableWidgetContainer<Content: View>: View {
    @ObservedObject var widgetManager: WidgetManager
    let widgetType: HomeWidgetType
    let content: () -> Content
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isLongPressing = false
    
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
        ZStack(alignment: .topTrailing) {
            content()
                .scaleEffect(widgetManager.isEditMode ? 0.95 : 1.0)
                .opacity(isDragging ? 0.8 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            widgetManager.isEditMode ? 
                                (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)) :
                                Color.clear,
                            lineWidth: 2
                        )
                        .animation(.easeInOut(duration: 0.2), value: widgetManager.isEditMode)
                )
            
            // Remove button (only in edit mode)
            if widgetManager.isEditMode {
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
                .offset(x: 8, y: -8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .offset(dragOffset)
        .zIndex(isDragging ? 100 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: widgetManager.isEditMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .updating($isLongPressing) { value, state, _ in
                    state = value
                }
                .onEnded { _ in
                    if !widgetManager.isEditMode {
                        widgetManager.enterEditMode()
                    }
                }
        )
        .simultaneousGesture(
            widgetManager.isEditMode ?
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        dragOffset = .zero
                        
                        // Calculate new position based on drag distance
                        let verticalMovement = value.translation.height
                        if abs(verticalMovement) > 50 {
                            let direction = verticalMovement > 0 ? 1 : -1
                            let visibleWidgets = widgetManager.visibleWidgets
                            if let currentIndex = visibleWidgets.firstIndex(where: { $0.type == widgetType }) {
                                let newIndex = currentIndex + direction
                                if newIndex >= 0 && newIndex < visibleWidgets.count {
                                    widgetManager.moveWidget(widgetType, toIndex: newIndex)
                                }
                            }
                        }
                    }
                : nil
        )
        // Wobble animation in edit mode
        .rotationEffect(
            widgetManager.isEditMode ?
                Angle(degrees: isDragging ? 0 : Double.random(in: -1...1)) :
                Angle(degrees: 0)
        )
        .animation(
            widgetManager.isEditMode ?
                Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true) :
                .default,
            value: widgetManager.isEditMode
        )
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
            HStack(spacing: 12) {
                Image(systemName: widgetType.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(widgetType.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
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
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Edit Widgets")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    Button("Done") {
                        widgetManager.exitEditMode()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Hidden widgets section
                if !widgetManager.hiddenWidgets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hidden Widgets")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 8) {
                            ForEach(widgetManager.hiddenWidgets) { config in
                                AddWidgetButton(widgetManager: widgetManager, widgetType: config.type)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Tip
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    
                    Text("Drag widgets to reorder • Tap − to remove")
                        .font(.system(size: 13))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 100) // Space for tab bar
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

