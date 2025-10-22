import SwiftUI

struct NotesCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var notesManager = NotesManager.shared
    @Binding var selectedNoteToOpen: Note?
    @Binding var showingNewNoteSheet: Bool

    private var pinnedNotes: [Note] {
        Array(notesManager.pinnedNotes.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with pin icon and Add Note button
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("Notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                Spacer()

                Button(action: {
                    HapticManager.shared.selection()
                    showingNewNoteSheet = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 24, height: 24)

                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Notes list
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if pinnedNotes.isEmpty {
                        Text("No pinned notes")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(pinnedNotes) { note in
                            Button(action: {
                                HapticManager.shared.cardTap()
                                selectedNoteToOpen = note
                            }) {
                                HStack(spacing: 8) {
                                    // Note title
                                    Text(note.title)
                                        .font(.shadcnTextXs)
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(12)
    }
}

#Preview {
    NotesCardWidget(selectedNoteToOpen: .constant(nil), showingNewNoteSheet: .constant(false))
        .background(Color.shadcnBackground(.light))
}
