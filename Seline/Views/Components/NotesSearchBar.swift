import SwiftUI

struct NotesSearchBar: View {
    @Binding var searchText: String
    @Binding var showingFolderSidebar: Bool
    @Binding var selectedFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                TextField("Search notes...", text: $searchText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
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

            // Selected folder indicator
            if let folderId = selectedFolderId {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(notesManager.getFolderName(for: folderId))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: {
                        withAnimation {
                            selectedFolderId = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
                .padding(.horizontal, 20)
            }
        }
    }
}

#Preview {
    VStack {
        NotesSearchBar(searchText: .constant(""), showingFolderSidebar: .constant(false), selectedFolderId: .constant(nil))
        NotesSearchBar(searchText: .constant("Sample search"), showingFolderSidebar: .constant(false), selectedFolderId: .constant(nil))
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}