import SwiftUI

struct HeaderSection: View {
    @Binding var selectedTab: TabSelection
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // Centered user name
            MotivationalGreeting()
                .environmentObject(authManager)

            // Settings icon on the right
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
        .padding(.vertical, 4)
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
        .environmentObject(AuthenticationManager.shared)
}