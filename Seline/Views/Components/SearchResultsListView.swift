import SwiftUI

struct SearchResultsListView<Item: Identifiable>: View {
    var results: [Item]
    var emptyMessage: String
    var rowContent: (Item) -> AnyView
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if results.isEmpty {
                    Text(emptyMessage)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(results) { item in
                        rowContent(item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
