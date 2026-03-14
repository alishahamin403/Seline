import SwiftUI

struct EventsView: View {
    var isVisible: Bool = true

    var body: some View {
        ConversationSearchView(isVisible: isVisible)
    }
}

#Preview {
    EventsView()
}
