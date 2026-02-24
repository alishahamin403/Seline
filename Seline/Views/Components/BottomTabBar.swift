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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(TabSelection.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        selectedTab: $selectedTab,
                        colorScheme: colorScheme
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bottomPillBackground)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 0)
            .padding(.bottom, 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }

    private var bottomPillBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.62),
                            colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.34)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        }
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

    private var itemFillColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.13)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var itemStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
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
                .frame(width: 22, height: 22)
                .frame(width: 46, height: 36)
                .background(
                    Capsule()
                        .fill(itemFillColor)
                )
                .overlay(
                    Capsule()
                        .stroke(itemStrokeColor, lineWidth: 0.5)
                )
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
