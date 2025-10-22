import SwiftUI

struct HeaderSection: View {
    @Binding var selectedTab: TabSelection
    @Binding var searchText: String
    @Binding var showingVoiceAssistant: Bool
    @FocusState.Binding var isSearchFocused: Bool
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 8) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                TextField("Search...", text: $searchText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)

                Button(action: {
                    HapticManager.shared.selection()
                    showingVoiceAssistant = true
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark ?
                    Color(red: 0.15, green: 0.15, blue: 0.15) :
                    Color(red: 0.95, green: 0.95, blue: 0.95)
            )
            .cornerRadius(10)

            // Settings icon
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "person")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Color.clear)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    @FocusState var isSearchFocused: Bool

    return HeaderSection(
        selectedTab: .constant(.home),
        searchText: .constant(""),
        showingVoiceAssistant: .constant(false),
        isSearchFocused: $isSearchFocused
    )
    .environmentObject(AuthenticationManager.shared)
}