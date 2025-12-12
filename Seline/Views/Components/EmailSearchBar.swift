import SwiftUI

struct EmailSearchBar: View {
    @Binding var searchText: String
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isSearchFocused: Bool

    var onSearchChanged: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            // Search text field
            TextField("Search emails...", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .focused($isSearchFocused)
                .onChange(of: searchText) { newValue in
                    // Only trigger search if query is meaningful (2+ characters)
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 || newValue.isEmpty {
                        onSearchChanged(newValue)
                    }
                }
                .submitLabel(.search)
                .onSubmit {
                    // Trigger search on submit
                    onSearchChanged(searchText)
                }

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onSearchChanged("")
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
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
