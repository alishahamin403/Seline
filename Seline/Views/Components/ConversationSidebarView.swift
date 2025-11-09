import SwiftUI

struct ConversationSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var searchService = SearchService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isEditMode = false
    @State private var selectedConversationIds: Set<UUID> = []

    var isAnySelected: Bool {
        !selectedConversationIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            conversationsListView
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 380)
    }

    private var headerView: some View {
        VStack(spacing: 12) {
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                } else {
                    Text("Chats")
                        .font(.system(size: 18, weight: .bold))
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
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .cornerRadius(4)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }

                // Close button
                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // New Chat button
            Button(action: {
                HapticManager.shared.selection()
                searchService.startNewConversation()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Chat")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.15))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }

    private var conversationsListView: some View {
        Group {
            if searchService.savedConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 32))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .padding(.top, 40)

                    Text("No chats yet")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Recent Conversations section header
                        Text("Recent Conversations")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        VStack(spacing: 0) {
                            ForEach(searchService.savedConversations) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                }
            }
        }
    }

    private func conversationRow(_ conversation: SavedConversation) -> some View {
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
                searchService.loadConversation(withId: conversation.id)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if isEditMode {
                        Image(systemName: selectedConversationIds.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedConversationIds.contains(conversation.id) ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray)
                            .frame(width: 18)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversation.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .lineLimit(2)

                        Text(conversation.formattedDate)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                            .lineLimit(1)
                    }

                    Spacer()

                    if !isEditMode {
                        Text("\(conversation.messages.count)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Subtle divider
                if conversation != searchService.savedConversations.last {
                    Divider()
                        .padding(.horizontal, 16)
                        .opacity(0.3)
                }
            }
            .background(selectedConversationIds.contains(conversation.id) ? Color.gray.opacity(0.15) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !isEditMode {
                Button(role: .destructive, action: {
                    HapticManager.shared.selection()
                    searchService.deleteConversation(withId: conversation.id)
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                }
            }
        }
    }
}

#Preview {
    ConversationSidebarView(isPresented: .constant(true))
}
