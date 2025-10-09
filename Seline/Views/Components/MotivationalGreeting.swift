import SwiftUI

struct MotivationalGreeting: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme

    private var userName: String {
        authManager.currentUser?.profile?.name ?? "User"
    }

    var body: some View {
        Text(userName.uppercased())
            .font(FontManager.geist(size: 17, weight: .regular))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    MotivationalGreeting()
        .environmentObject(AuthenticationManager.shared)
        .padding()
}
