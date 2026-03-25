import SwiftUI

struct BottomTabBar: View {
    @Binding var selectedTab: PrimaryTab
    @Environment(\.colorScheme) var colorScheme

    private var topDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PrimaryTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    selectedTab: $selectedTab,
                    colorScheme: colorScheme
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(topDividerColor)
                .frame(height: 0.5)
        }
    }
}

struct TabButton: View {
    let tab: PrimaryTab
    @Binding var selectedTab: PrimaryTab
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedTab == tab
    }

    private var selectedColor: Color {
        Color.appTextPrimary(colorScheme)
    }

    private var unselectedColor: Color {
        Color.appTextSecondary(colorScheme)
    }

    private var iconColor: Color {
        isSelected ? selectedColor : unselectedColor
    }

    @ViewBuilder
    private var tabIcon: some View {
        if tab == .home {
            Image("HomeTabIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else if tab == .chat {
            Image("AITabSIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else if tab == .notes {
            Image("NoteTabIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else if tab == .maps {
            Image("MapTabIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else if tab == .search {
            Image(systemName: isSelected ? tab.filledSystemIcon : tab.systemIcon)
                .font(.system(size: 20, weight: .regular))
        } else {
            Image(systemName: isSelected ? tab.filledSystemIcon : tab.systemIcon)
                .font(.system(size: 20, weight: .regular))
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.tabChange()
            selectedTab = tab
        }) {
            tabIcon
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack {
        Spacer()
        BottomTabBar(selectedTab: .constant(.home))
    }
}
