import SwiftUI

enum TabSelection: String, CaseIterable {
    case home = "house"
    case email = "envelope"
    case events = "calendar"
    case notes = "square.and.pencil"
    case maps = "location.circle"

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
        case .notes: return "square.and.pencil"
        case .maps: return "location.circle.fill"
        }
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: TabSelection
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var tabIndicator
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Sliding indicator
            GeometryReader { geometry in
                let tabWidth = geometry.size.width / CGFloat(TabSelection.allCases.count)
                let currentIndex = CGFloat(TabSelection.allCases.firstIndex(of: selectedTab) ?? 0)
                let indicatorOffset = (currentIndex * tabWidth) + (tabWidth / 2) - 20
                
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                    .frame(width: 40, height: 3)
                    .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                    .offset(x: indicatorOffset)
                    .animation(.smoothTabTransition, value: selectedTab)
            }
            .frame(height: 3)
            .padding(.bottom, 44)
            
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
            .padding(.bottom, 8)
        }
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
            HapticManager.shared.tabChange()
            withAnimation(.smoothTabTransition) {
                selectedTab = tab
            }
        }) {
            Image(systemName: isSelected ? tab.filledIcon : tab.rawValue)
                .font(FontManager.geist(size: .title1, weight: .medium))
                .foregroundColor(
                    isSelected ? selectedColor : .gray
                )
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.smoothTabTransition, value: isSelected)
    }
}

#Preview {
    VStack {
        Spacer()
        BottomTabBar(selectedTab: .constant(.home))
    }
}