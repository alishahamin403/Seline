import SwiftUI

struct ConversationHistoryView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var selectedConversation: SavedConversation?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: {
                    HapticManager.shared.selection()
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
                .buttonStyle(PlainButtonStyle())

                Text("Conversation History")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

            Divider()

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
                                HapticManager.shared.selection()
                                selectedConversation = conversation
                                searchService.loadConversation(withId: conversation.id)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 12) {
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

                                        HStack(spacing: 6) {
                                            Image(systemName: "bubble.left.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                            Text("\(conversation.messages.count)")
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                        }
                                    }

                                    // Message preview
                                    if let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
                                        Text(firstUserMessage.text)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Divider()
                                .padding(.leading, 16)
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
