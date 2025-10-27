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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EmailTab.allCases, id: \.self) { tab in
                EmailTabButton(
                    tab: tab,
                    selectedTab: $selectedTab,
                    colorScheme: colorScheme
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.gray.opacity(0.08))
        )
    }
}

struct EmailTabButton: View {
    let tab: EmailTab
    @Binding var selectedTab: EmailTab
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedTab == tab
    }

    private var selectedColor: Color {
        // Matches + sign button fill color - #333333
        return Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    private var backgroundColor: Color {
        if isSelected {
            return selectedColor
        }
        return Color.clear
    }

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            HStack(spacing: ShadcnSpacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))

                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(
                isSelected ? .white : .gray
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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
