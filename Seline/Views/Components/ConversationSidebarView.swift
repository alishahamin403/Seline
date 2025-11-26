import SwiftUI

struct ConversationSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var searchService = SearchService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isEditMode = false
    @State private var selectedConversationIds: Set<UUID> = []
    @State private var hoveredConversationId: UUID?

    var isAnySelected: Bool {
        !selectedConversationIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    headerView
                    conversationsListView
                        .frame(maxHeight: .infinity)

                    Spacer()
                        .frame(height: 100)
                }
            }

            // Sticky Footer - New Chat button
            VStack(spacing: 0) {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                Button(action: {
                    HapticManager.shared.buttonTap()
                    searchService.startNewConversation()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .medium))
                        Text("New Chat")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.29, green: 0.29, blue: 0.29))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            (colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.98, green: 0.98, blue: 0.98))
                .ignoresSafeArea()
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)
        .frame(minWidth: 300, idealWidth: UIScreen.main.bounds.width * 0.75, maxWidth: UIScreen.main.bounds.width * 0.75)
        .onAppear {
            // Load saved conversations from local storage when sidebar appears
            searchService.loadConversationHistoryLocally()
        }
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
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                } else {
                    Text("Chats")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
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
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    private var conversationsListView: some View {
        Group {
            if searchService.savedConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2))

                    Text("No chats yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                    Text("Start a new conversation to begin")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // Recent Conversations section header
                    HStack {
                        Text("RECENT CONVERSATIONS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

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
                HapticManager.shared.light()
                searchService.loadConversation(withId: conversation.id)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            }
        }) {
            HStack(spacing: 8) {
                if isEditMode {
                    Image(systemName: selectedConversationIds.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedConversationIds.contains(conversation.id) ? .white : .gray)
                        .frame(width: 20)
                        .animation(.easeInOut(duration: 0.2), value: selectedConversationIds)
                }

                Image(systemName: "bubble.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedConversationIds.contains(conversation.id) ? .white : (colorScheme == .dark ? .white : .black))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.system(size: 14, weight: selectedConversationIds.contains(conversation.id) ? .semibold : .medium))
                        .foregroundColor(selectedConversationIds.contains(conversation.id) ? .white : (colorScheme == .dark ? .white : .black))
                        .lineLimit(1)

                    Text(conversation.formattedDate)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(selectedConversationIds.contains(conversation.id) ? .white.opacity(0.8) : (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)))
                        .lineLimit(1)
                }

                Spacer()

                if !isEditMode {
                    Text("\(conversation.messages.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selectedConversationIds.contains(conversation.id) ? .white.opacity(0.8) : (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(getRowBackgroundColor(for: conversation))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(getRowBorderColor(for: conversation), lineWidth: 0.5)
            )
            .shadow(
                color: getRowShadowColor(for: conversation),
                radius: getRowShadowRadius(for: conversation),
                x: 0,
                y: getRowShadowY(for: conversation)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .animation(.easeInOut(duration: 0.2), value: hoveredConversationId)
            .contentShape(Rectangle())
            .onHover { isHovering in
                hoveredConversationId = isHovering ? conversation.id : nil
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            if !isEditMode {
                Button(role: .destructive, action: {
                    HapticManager.shared.delete()
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

    private func getRowBackgroundColor(for conversation: SavedConversation) -> Color {
        if selectedConversationIds.contains(conversation.id) {
            return Color(red: 0.29, green: 0.29, blue: 0.29)
        } else if hoveredConversationId == conversation.id {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
        } else {
            return Color.clear
        }
    }

    private func getRowBorderColor(for conversation: SavedConversation) -> Color {
        if selectedConversationIds.contains(conversation.id) {
            return Color.white.opacity(0.1)
        } else if hoveredConversationId == conversation.id {
            return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func getRowShadowColor(for conversation: SavedConversation) -> Color {
        if hoveredConversationId == conversation.id {
            return colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func getRowShadowRadius(for conversation: SavedConversation) -> CGFloat {
        hoveredConversationId == conversation.id ? 6 : 0
    }

    private func getRowShadowY(for conversation: SavedConversation) -> CGFloat {
        hoveredConversationId == conversation.id ? 2 : 0
    }
}

#Preview {
    ConversationSidebarView(isPresented: .constant(true))
}
