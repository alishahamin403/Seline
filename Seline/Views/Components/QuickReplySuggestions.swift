import SwiftUI

struct QuickReplySuggestions: View {
    let suggestions: [String]
    let onSuggestionTapped: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested follow-ups")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        onSuggestionTapped(suggestion)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)

                            Text(suggestion)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.blue)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.blue.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }
}

#Preview {
    QuickReplySuggestions(
        suggestions: [
            "What about next week?",
            "Can you reschedule it?",
            "Show me free slots?"
        ],
        onSuggestionTapped: { suggestion in
            print("Tapped: \(suggestion)")
        }
    )
}
