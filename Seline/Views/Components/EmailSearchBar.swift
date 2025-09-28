import SwiftUI

struct EmailSearchBar: View {
    @Binding var searchText: String
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isSearchFocused: Bool

    var onSearchChanged: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: .title3, weight: .regular))
                .foregroundColor(.gray)

            // Search text field
            TextField("Search emails...", text: $searchText)
                .font(FontManager.geist(size: .title3, weight: .regular))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .focused($isSearchFocused)
                .onChange(of: searchText, perform: onSearchChanged)
                .submitLabel(.search)

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onSearchChanged("")
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: .title3, weight: .regular))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, ShadcnSpacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
        )
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }
}

#Preview {
    VStack(spacing: 20) {
        EmailSearchBar(
            searchText: .constant(""),
            onSearchChanged: { _ in }
        )
        EmailSearchBar(
            searchText: .constant("project update"),
            onSearchChanged: { _ in }
        )
    }
    .padding()
}
