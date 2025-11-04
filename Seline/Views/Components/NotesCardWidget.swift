import SwiftUI

struct NotesCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var notesManager = NotesManager.shared
    @Binding var selectedNoteToOpen: Note?
    @Binding var showingNewNoteSheet: Bool

    private var pinnedNotes: [Note] {
        Array(notesManager.pinnedNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            contentSection
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.97, green: 0.97, blue: 0.97))
        )
        .padding(.horizontal, 12)
    }

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text("PINNED")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text("(\\(pinnedNotes.count))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }

            Spacer()

            Button(action: {
                HapticManager.shared.selection()
                showingNewNoteSheet = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
    }

    private var contentSection: some View {
        Group {
            if pinnedNotes.isEmpty {
                emptyStateView
            } else {
                notesListView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

            Text("No pinned notes")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var notesListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(pinnedNotes.prefix(4)) { note in
                    noteCardButton(for: note)
                }

                if pinnedNotes.count > 4 {
                    moreNotesButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func noteCardButton(for note: Note) -> some View {
        Button(action: {
            HapticManager.shared.cardTap()
            selectedNoteToOpen = note
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)

                        if !note.content.isEmpty {
                            Text(note.content)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var moreNotesButton: some View {
        Button(action: { /* Navigate to notes view */ }) {
            Text("+ \\(pinnedNotes.count - 4) more notes")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NotesCardWidget(selectedNoteToOpen: .constant(nil), showingNewNoteSheet: .constant(false))
        .background(Color.shadcnBackground(.light))
}
