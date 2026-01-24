import SwiftUI

struct HomeSectionButton: View {
    let title: String
    let titleContent: (() -> AnyView)?
    let unreadCount: Int?
    let detailContent: () -> AnyView
    let onAddAction: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded: Bool = false

    // Original initializer for backward compatibility
    init(title: String, unreadCount: Int? = nil, onAddAction: (() -> Void)? = nil, @ViewBuilder detailContent: @escaping () -> AnyView = { AnyView(EmptyView()) }) {
        self.title = title
        self.titleContent = nil
        self.unreadCount = unreadCount
        self.onAddAction = onAddAction
        self.detailContent = detailContent
    }

    // New initializer for custom title content with icons
    init(titleContent: @escaping () -> AnyView, unreadCount: Int? = nil, onAddAction: (() -> Void)? = nil, @ViewBuilder detailContent: @escaping () -> AnyView = { AnyView(EmptyView()) }) {
        self.title = ""
        self.titleContent = titleContent
        self.unreadCount = unreadCount
        self.onAddAction = onAddAction
        self.detailContent = detailContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main button with title and badge
            Button(action: {
                if let count = unreadCount, count > 0 {
                    HapticManager.shared.cardTap()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack {
                    if let titleContent = titleContent {
                        titleContent()
                    } else {
                        Text(title)
                            .font(FontManager.geist(size: 24, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let unreadCount = unreadCount, unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(FontManager.geist(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                )
                        }

                        if let onAddAction = onAddAction {
                            Button(action: {
                                HapticManager.shared.buttonTap()
                                onAddAction()
                            }) {
                                Image(systemName: "plus")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.clear)
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable detail content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    detailContent()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.clear)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            HomeSectionButton(title: "EMAIL")
            HomeSectionButton(title: "EVENTS")
        }
        HStack(spacing: 16) {
            HomeSectionButton(title: "NOTES")
            HomeSectionButton(title: "MAPS")
        }
    }
    .padding(.horizontal, 20)
    .background(Color.shadcnBackground(.light))
}