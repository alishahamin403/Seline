import SwiftUI

enum TabSelection: String, CaseIterable {
    case home = "house"
    case email = "envelope"
    case events = "calendar"
    case notes = "note.text"
    case maps = "map"

    var title: String {
        switch self {
        case .home: return "Home"
        case .email: return "Email"
        case .events: return "Events"
        case .notes: return "Notes"
        case .maps: return "Maps"
        }
    }

    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .email: return "envelope.fill"
        case .events: return "calendar"
        case .notes: return "note.text"
        case .maps: return "map.fill"
        }
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: TabSelection
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabSelection.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    selectedTab: $selectedTab,
                    colorScheme: colorScheme
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

struct TabButton: View {
    let tab: TabSelection
    @Binding var selectedTab: TabSelection
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedTab == tab
    }

    // Black/white theme colors for selected state
    private var selectedColor: Color {
        if colorScheme == .dark {
            // White for dark mode
            return Color.white
        } else {
            // Black for light mode
            return Color.black
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.tabChange()
            selectedTab = tab
        }) {
            Image(systemName: isSelected ? tab.filledIcon : tab.rawValue)
                .font(FontManager.geist(size: .title1, weight: .medium))
                .foregroundColor(
                    isSelected ? selectedColor : .gray
                )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack {
        Spacer()
        BottomTabBar(selectedTab: .constant(.home))
    }
}