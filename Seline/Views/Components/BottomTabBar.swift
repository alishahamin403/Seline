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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabSelection.allCases, id: \.self) { tab in
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
    }
}

struct TabButton: View {
    let tab: TabSelection
    @Binding var selectedTab: TabSelection
    let colorScheme: ColorScheme

    private var isSelected: Bool {
        selectedTab == tab
    }

    private var selectedColor: Color {
        (colorScheme == .dark ? Color.white : Color.black)
    }

    private var unselectedColor: Color {
        (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
    }

    private var iconColor: Color {
        isSelected ? selectedColor : unselectedColor
    }

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            Group {
                if tab == .home {
                    Image("HomeTabIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else if tab == .email {
                    Image("EmailTabIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else if tab == .events {
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
                } else {
                    Image(systemName: isSelected ? tab.filledIcon : tab.rawValue)
                        .font(.system(size: 20, weight: .regular))
                }
            }
            .foregroundColor(iconColor)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
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
