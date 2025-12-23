import SwiftUI

struct FloatingAIBar: View {
    @Environment(\.colorScheme) var colorScheme
    var onTap: (() -> Void)? = nil
    
    // Time-based greeting text
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "How can I help you this morning?"
        case 12..<17: return "How can I help you this afternoon?"
        case 17..<21: return "How can I help you this evening?"
        default: return "How can I help you tonight?"
        }
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onTap?()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
                
                Text(greetingText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark ? [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.15)
                            ] : [
                                Color.black.opacity(0.1),
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 20, x: 0, y: 8)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 8, x: 0, y: 4)
    }
}

