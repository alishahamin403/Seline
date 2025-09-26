import SwiftUI

struct HeaderSection: View {
    @Binding var selectedTab: TabSelection
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }

    var body: some View {
        ZStack {
            // Centered date display
            Text(dateFormatter.string(from: Date()))
                .font(FontManager.geist(size: 20, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            // Profile icon positioned on the right
            HStack {
                Spacer()
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "person.circle")
                        .font(FontManager.geist(size: 24, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    @State var selectedTab: TabSelection = .home
    return HeaderSection(selectedTab: $selectedTab)
}