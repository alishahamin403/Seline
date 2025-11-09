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
        .frame(maxWidth: 280)
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
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .border(Color.gray.opacity(0.2), width: 0.5)
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
                    VStack(spacing: 0) {
                        ForEach(searchService.savedConversations) { conversation in
                            conversationRow(conversation)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditMode {
                        Image(systemName: selectedConversationIds.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedConversationIds.contains(conversation.id) ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray)
                            .frame(width: 18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .lineLimit(1)

                        Text(conversation.formattedDate)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }

                    Spacer()

                    if !isEditMode {
                        Text("\(conversation.messages.count)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }

                if !isEditMode, let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
                    Text(firstUserMessage.text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, isEditMode ? 0 : 24)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedConversationIds.contains(conversation.id) ? Color.gray.opacity(0.1) : Color.clear)
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
