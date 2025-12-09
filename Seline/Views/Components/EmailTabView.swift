import SwiftUI

enum EmailTab: String, CaseIterable {
    case inbox = "Inbox"
    case sent = "Sent"

    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        }
    }

    var folder: EmailFolder {
        switch self {
        case .inbox: return .inbox
        case .sent: return .sent
        }
    }
}

struct EmailTabView: View {
    @Binding var selectedTab: EmailTab
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EmailTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: ShadcnSpacing.sm) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))

                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(tabForegroundColor(isSelected: isSelected))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
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
        )
    }

    // MARK: - Helper Functions for Pill Buttons

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
        }
    }

    private func tabBackgroundColor() -> Color {
        return colorScheme == .dark ? .white : .black
    }

    private func tabContainerColor() -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
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
