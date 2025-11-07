import SwiftUI

struct QuickReplySuggestions: View {
    let suggestions: [String]
    let onSuggestionTapped: (String) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(action: {
                    onSuggestionTapped(suggestion)
                }) {
                    HStack(spacing: 12) {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
