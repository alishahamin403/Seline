import SwiftUI

/// Displays clarification options for ambiguous queries
/// Allows user to select from multiple choice options instead of typing
struct ClarificationPromptView: View {
    let question: String  // e.g., "What type of folders are you asking about?"
    let options: [ClarificationOption]  // Multiple choice options
    let onSelect: (String) -> Void  // Called when user selects an option
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            Text(question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            // Options as buttons
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options, id: \.id) { option in
                    Button(action: {
                        onSelect(option.action)
                    }) {
                        HStack(spacing: 10) {
                            if let emoji = option.emoji {
                                Text(emoji)
                                    .font(.system(size: 14))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.text)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                if let subtitle = option.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ClarificationOption: Identifiable {
    let id: UUID
    let text: String  // "Email folders"
    let subtitle: String?  // Optional description
    let emoji: String?  // Optional emoji
    let action: String  // What to send as the message

    init(text: String, subtitle: String? = nil, emoji: String? = nil, action: String, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.subtitle = subtitle
        self.emoji = emoji
        self.action = action
    }
}

#Preview {
    ClarificationPromptView(
        question: "Which folders would you like to see?",
        options: [
            ClarificationOption(text: "Email folders", subtitle: "Gmail, Outlook, etc.", emoji: "📧", action: "email folders"),
            ClarificationOption(text: "Note folders", subtitle: "Organized by topic", emoji: "📝", action: "note folders"),
            ClarificationOption(text: "Both", subtitle: "Show me everything", emoji: "📚", action: "show all folders")
        ],
        onSelect: { _ in }
    )
    .padding()
}
