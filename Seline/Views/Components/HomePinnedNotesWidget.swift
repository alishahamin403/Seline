import SwiftUI

/// Combined inbox widget for unread emails + pinned notes
struct HomePinnedNotesWidget: View {
    private enum FocusTab: String, CaseIterable {
        case mail = "Mail"
        case notes = "Notes"
    }

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var emailService = EmailService.shared

    @Binding var selectedTab: TabSelection
    @Binding var showingNewNoteSheet: Bool

    var onNoteSelected: ((Note) -> Void)?
    var onEmailSelected: ((Email) -> Void)?

    @State private var activeTab: FocusTab = .mail

    private var cardHeadingFont: Font {
        FontManager.geist(size: 20, weight: .semibold)
    }

    private var unreadEmails: [Email] {
        emailService.inboxEmails.filter { !$0.isRead }
    }

    private var pinnedNotes: [Note] {
        notesManager.pinnedNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            tabPicker

            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1))

            if activeTab == .mail {
                mailContent
            } else {
                notesContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 10,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Inbox")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text("Focus Inbox")
                    .font(cardHeadingFont)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }

            Spacer()

            if activeTab == .notes {
                Button(action: {
                    HapticManager.shared.selection()
                    showingNewNoteSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1), lineWidth: 0.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .allowsParentScrolling()
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(FocusTab.allCases, id: \.self) { tab in
                Button(action: {
                    HapticManager.shared.selection()
                    activeTab = tab
                }) {
                    Text(tab.rawValue)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(activeTab == tab
                            ? (colorScheme == .dark ? .black : .white)
                            : (colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.68)))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(activeTab == tab
                                    ? (colorScheme == .dark ? Color.white : Color.black)
                                    : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .allowsParentScrolling()
            }

            Spacer()
        }
    }

    private var mailContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if unreadEmails.isEmpty {
                Text("All caught up")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
                    .padding(.vertical, 4)
            } else {
                ForEach(unreadEmails.prefix(3), id: \.id) { email in
                    Button(action: {
                        HapticManager.shared.email()
                        onEmailSelected?(email)
                    }) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email.sender.displayName)
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)

                                Text(email.subject)
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.62))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(email.formattedTime)
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .allowsParentScrolling()
                }
            }

            viewAllButton(title: "Open Mail", tab: .email)
        }
    }

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pinnedNotes.isEmpty {
                Text("No pinned notes")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
                    .padding(.vertical, 4)
            } else {
                ForEach(pinnedNotes.prefix(3), id: \.id) { note in
                    Button(action: {
                        HapticManager.shared.cardTap()
                        onNoteSelected?(note)
                    }) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)

                                Text(note.formattedDateModified)
                                    .font(FontManager.geist(size: 11, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .allowsParentScrolling()
                }
            }

            viewAllButton(title: "Open Notes", tab: .notes)
        }
    }

    private func viewAllButton(title: String, tab: TabSelection) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            selectedTab = tab
        }) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
        .frame(maxWidth: .infinity, alignment: .leading)
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
