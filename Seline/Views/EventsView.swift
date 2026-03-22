import SwiftUI

struct ChatView: View {
    var isVisible: Bool = true

    var body: some View {
        ConversationSearchView(isVisible: isVisible)
    }
}

#Preview {
    ChatView()
}
