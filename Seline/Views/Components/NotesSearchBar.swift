import SwiftUI

struct NotesSearchBar: View {
    @Binding var searchText: String
    @Binding var showingFolderSidebar: Bool
    @Binding var selectedFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Folders button
                Button(action: {
                    withAnimation {
                        showingFolderSidebar.toggle()
                    }
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)

                    TextField("Search notes...", text: $searchText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                )
            }

            // Selected folder indicator
            if let folderId = selectedFolderId {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))

                    Text(notesManager.getFolderName(for: folderId))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: {
                        withAnimation {
                            selectedFolderId = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80).opacity(0.2) : Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.1))
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, selectedFolderId == nil ? 20 : 0)
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