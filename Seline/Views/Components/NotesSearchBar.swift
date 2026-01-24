import SwiftUI

struct NotesSearchBar: View {
    @Binding var searchText: String
    @Binding var showingFolderSidebar: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // Search bar only
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(.gray)

            TextField("Search notes...", text: $searchText)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(FontManager.geist(size: 14, weight: .medium))
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
    }
}

#Preview {
    VStack(spacing: 12) {
        NotesSearchBar(searchText: .constant(""), showingFolderSidebar: .constant(false))
        NotesSearchBar(searchText: .constant("Sample search"), showingFolderSidebar: .constant(false))
    }
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}