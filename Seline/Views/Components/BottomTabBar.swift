import SwiftUI

enum TabSelection: String, CaseIterable {
    case home = "house"
    case email = "envelope"
    case events = "sparkles"
    case notes = "square.and.pencil"
    case maps = "map"

    var title: String {
        switch self {
        case .home: return "Home"
        case .email: return "Email"
        case .events: return "Chat"
        case .notes: return "Notes"
        case .maps: return "Maps"
        }
    }

    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .email: return "envelope.fill"
        case .events: return "sparkles"
        case .notes: return "square.and.pencil"
        case .maps: return "map.fill"
        }
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: TabSelection
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var tabIndicator
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabSelection.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    selectedTab: $selectedTab,
                    colorScheme: colorScheme,
                    namespace: tabIndicator
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 0)
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
    var namespace: Namespace.ID

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
            // Removed haptic feedback on tab change for smoother feel
            // Switch tabs immediately without animation for snappy transitions
            selectedTab = tab
        }) {
            Image(systemName: isSelected ? tab.filledIcon : tab.rawValue)
                .font(FontManager.geist(size: .title1, weight: .medium))
                .foregroundColor(
                    isSelected ? selectedColor : .gray
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
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