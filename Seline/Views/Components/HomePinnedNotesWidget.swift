import SwiftUI

/// A minimalistic pinned notes widget for the home screen
struct HomePinnedNotesWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var notesManager = NotesManager.shared
    
    @Binding var selectedTab: TabSelection
    @Binding var showingNewNoteSheet: Bool
    var onNoteSelected: ((Note) -> Void)?
    
    private var pinnedNotes: [Note] {
        notesManager.pinnedNotes
    }
    
    private var pinnedCount: Int {
        pinnedNotes.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Text("Pinned Notes")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // Add note button
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    )
                    .onTapGesture {
                        HapticManager.shared.selection()
                        showingNewNoteSheet = true
                    }
            }
            
            // Notes list
            if pinnedNotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    
                    Text("No pinned notes yet")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    
                    Text("Pin important notes to see them here")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pinnedNotes.prefix(5)) { note in
                        noteRow(note)
                    }
                    
                    // Show "more" indicator if there are more notes
                    if pinnedCount > 5 {
                        HStack(spacing: 6) {
                            Text("+\(pinnedCount - 5) more pinned")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.shared.selection()
                            selectedTab = .notes
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                // Last updated and folder info (same as notes page)
                HStack(spacing: 8) {
                    Text(note.formattedDateModified)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    
                    if let folderId = note.folderId {
                        Text("•")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        
                        Text(notesManager.getFolderName(for: folderId))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.cardTap()
            onNoteSelected?(note)
        }
    }
}

#Preview {
    VStack {
        HomePinnedNotesWidget(
            selectedTab: .constant(.home),
            showingNewNoteSheet: .constant(false)
        )
        .padding(.horizontal, 12)
        Spacer()
    }
    .background(Color.shadcnBackground(.dark))
}

