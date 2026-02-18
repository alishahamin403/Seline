import SwiftUI

struct InteractiveSidebarOverlay<SidebarContent: View>: View {
    @Binding var isPresented: Bool
    let canOpen: Bool
    let sidebarWidth: CGFloat
    let colorScheme: ColorScheme
    let sidebarContent: () -> SidebarContent

    @State private var dragMode: DragMode? = nil
    @State private var dragOffset: CGFloat = 0

    private enum DragMode {
        case opening
        case closing
    }

    init(
        isPresented: Binding<Bool>,
        canOpen: Bool = true,
        sidebarWidth: CGFloat,
        colorScheme: ColorScheme,
        @ViewBuilder sidebarContent: @escaping () -> SidebarContent
    ) {
        self._isPresented = isPresented
        self.canOpen = canOpen
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        self.sidebarContent = sidebarContent
    }

    private var isDragging: Bool {
        dragMode != nil
    }

    private var shouldRenderOverlay: Bool {
        isPresented || isDragging
    }

    private var currentSidebarOffset: CGFloat {
        switch dragMode {
        case .opening:
            return -sidebarWidth + dragOffset
        case .closing:
            return dragOffset
        case .none:
            return isPresented ? 0 : -sidebarWidth
        }
    }

    private var openProgress: CGFloat {
        let progress = 1 + (currentSidebarOffset / sidebarWidth)
        return min(1, max(0, progress))
    }

    private var spring: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.height) < 80 else { return }

                if dragMode == nil {
                    if isPresented {
                        if value.startLocation.x <= sidebarWidth + 24 {
                            dragMode = .closing
                        } else {
                            return
                        }
                    } else {
                        if canOpen && value.startLocation.x <= 28 {
                            dragMode = .opening
                        } else {
                            return
                        }
                    }
                }

                switch dragMode {
                case .opening:
                    dragOffset = min(max(value.translation.width, 0), sidebarWidth)
                case .closing:
                    dragOffset = min(max(value.translation.width, -sidebarWidth), 0)
                case .none:
                    break
                }
            }
            .onEnded { value in
                guard let mode = dragMode else { return }

                let predictedX = value.predictedEndTranslation.width
                withAnimation(spring) {
                    switch mode {
                    case .opening:
                        let progress = dragOffset / sidebarWidth
                        let predictedProgress = max(predictedX, 0) / sidebarWidth
                        isPresented = progress > 0.35 || predictedProgress > 0.5
                    case .closing:
                        let progress = abs(dragOffset) / sidebarWidth
                        let predictedProgress = max(-predictedX, 0) / sidebarWidth
                        isPresented = !(progress > 0.35 || predictedProgress > 0.5)
                    }
                }

                dragOffset = 0
                dragMode = nil
            }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if shouldRenderOverlay {
                Color.black
                    .opacity(0.42 * openProgress)
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
                        .background(colorScheme == .dark ? Color.black : Color(white: 0.99))
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                                .frame(width: 1)
                        }
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16),
                            radius: 24,
                            x: 6,
                            y: 0
                        )
                        .offset(x: currentSidebarOffset)

                    Spacer(minLength: 0)
                }
                .simultaneousGesture(dragGesture)
            } else if canOpen {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 24)
                        .contentShape(Rectangle())
                        .highPriorityGesture(dragGesture)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
