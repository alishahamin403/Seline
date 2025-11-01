import SwiftUI

struct ConversationHistoryView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var selectedConversation: SavedConversation?
    @State private var isEditMode = false
    @State private var selectedConversationIds: Set<UUID> = []

    var isAnySelected: Bool {
        !selectedConversationIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                if isEditMode {
                    Button(action: {
                        if selectedConversationIds.count == searchService.savedConversations.count {
                            selectedConversationIds.removeAll()
                        } else {
                            selectedConversationIds = Set(searchService.savedConversations.map { $0.id })
                        }
                    }) {
                        Text(selectedConversationIds.count == searchService.savedConversations.count ? "Deselect All" : "Select All")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))
                    }
                } else {
                    Text("Conversations")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }

                Spacer()

                if isEditMode && isAnySelected {
                    Button(action: {
                        HapticManager.shared.delete()
                        for id in selectedConversationIds {
                            searchService.deleteConversation(withId: id)
                        }
                        selectedConversationIds.removeAll()
                        isEditMode = false
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Delete")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                }

                Button(action: {
                    HapticManager.shared.selection()
                    if isEditMode {
                        selectedConversationIds.removeAll()
                    }
                    isEditMode.toggle()
                }) {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

            // Conversations list
            if searchService.savedConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .padding(.top, 60)

                    Text("No conversations yet")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(searchService.savedConversations) { conversation in
                            Button(action: {
                                if isEditMode {
                                    HapticManager.shared.selection()
                                    if selectedConversationIds.contains(conversation.id) {
                                        selectedConversationIds.remove(conversation.id)
                                    } else {
                                        selectedConversationIds.insert(conversation.id)
                                    }
                                } else {
                                    HapticManager.shared.selection()
                                    selectedConversation = conversation
                                    searchService.loadConversation(withId: conversation.id)
                                    dismiss()
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 12) {
                                        if isEditMode {
                                            Image(systemName: selectedConversationIds.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(selectedConversationIds.contains(conversation.id) ? (colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40)) : Color.gray)
                                                .frame(width: 24)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(conversation.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                                .lineLimit(1)

                                            Text(conversation.formattedDate)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                        }

                                        Spacer()

                                        if !isEditMode {
                                            HStack(spacing: 6) {
                                                Image(systemName: "bubble.left.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                                Text("\(conversation.messages.count)")
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                            }
                                        }
                                    }

                                    // Message preview
                                    if !isEditMode, let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
                                        Text(firstUserMessage.text)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(selectedConversationIds.contains(conversation.id) ? Color.gray.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu(ContextMenu(menuItems: {
                                Button(role: .destructive, action: {
                                    HapticManager.shared.selection()
                                    searchService.deleteConversation(withId: conversation.id)
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete")
                                    }
                                }
                            }), shouldShowMenu: !isEditMode)
                        }
                    }
                }
            }
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }
}

#Preview {
    ConversationHistoryView()
}
