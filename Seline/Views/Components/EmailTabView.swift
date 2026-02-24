import SwiftUI

enum EmailTab: String, CaseIterable {
    case inbox = "Inbox"
    case sent = "Sent"
    case events = "Events"

    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .events: return "calendar"
        }
    }

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .events: return "Calendar"
        }
    }

    var folder: EmailFolder {
        switch self {
        case .inbox: return .inbox
        case .sent: return .sent
        case .events: return .inbox // Events tab doesn't need a folder
        }
    }
}

struct EmailTabView: View {
    @Binding var selectedTab: EmailTab
    var onTabTapped: ((EmailTab, Bool) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EmailTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button(action: {
                    HapticManager.shared.selection()
                    let isReselect = selectedTab == tab
                    onTabTapped?(tab, isReselect)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.displayName)
                        .font(FontManager.geist(size: 12, systemWeight: .semibold))
                        .foregroundColor(tabForegroundColor(isSelected: isSelected))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(tabBackgroundColor())
                                .matchedGeometryEffect(id: "emailTab", in: tabAnimation)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(tabContainerColor())
                .overlay(
                    Capsule()
                        .stroke(tabContainerStrokeColor(), lineWidth: 1)
                )
        )
    }

    // MARK: - Helper Functions for Pill Buttons

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color.emailLightTextSecondary
        }
    }

    private func tabBackgroundColor() -> Color {
        colorScheme == .dark ? Color.claudeAccent.opacity(0.95) : Color.claudeAccent
    }

    private func tabContainerColor() -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightChipIdle
    }

    private func tabContainerStrokeColor() -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.emailLightBorder
    }
}

#Preview {
    VStack(spacing: 20) {
        EmailTabView(selectedTab: .constant(.inbox))
        EmailTabView(selectedTab: .constant(.sent))
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}
