import SwiftUI

struct HeaderSection: View {
    @Binding var selectedTab: TabSelection
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 0) {
            // Sun/Moon tracker extending across most of the width
            SunMoonTimeTracker()

            // Settings icon on the right with some padding
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "person.circle")
                    .font(FontManager.geist(size: 24, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark ? Color.gmailDarkBackground : Color.white
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    HeaderSection(selectedTab: .constant(.home))
}