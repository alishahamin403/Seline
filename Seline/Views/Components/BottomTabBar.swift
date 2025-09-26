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
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .top
        )
    }
}

struct TabButton: View {
    let tab: TabSelection
    @Binding var selectedTab: TabSelection
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedTab == tab
    }

    // Blue theme colors for selected state
    private var selectedColor: Color {
        if colorScheme == .dark {
            // Light blue for dark mode - #84cae9
            return Color(red: 0.518, green: 0.792, blue: 0.914)
        } else {
            // Dark blue for light mode - #345766
            return Color(red: 0.20, green: 0.34, blue: 0.40)
        }
    }

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            Image(systemName: isSelected ? tab.filledIcon : tab.rawValue)
                .font(FontManager.geist(size: .title1, weight: .medium))
                .foregroundColor(
                    isSelected ? selectedColor : .gray
                )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    @State var selectedTab: TabSelection = .home

    return VStack {
        Spacer()
        BottomTabBar(selectedTab: $selectedTab)
    }
}