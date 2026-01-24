import SwiftUI

// MARK: - Proactive Question Card

struct ProactiveQuestionCard: View {
    let locationName: String
    let question: String
    let onAnswer: (String) async -> Void
    @Environment(\.colorScheme) var colorScheme
    
    @State private var answerText = ""
    @State private var isSubmitting = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question text
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.blue.opacity(0.8) : Color.blue)
                
                Text(question)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            
            // Answer input field
            HStack(spacing: 8) {
                TextField("Type your answer...", text: $answerText, axis: .vertical)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                    .focused($isInputFocused)
                    .lineLimit(2...4)
                
                // Submit button
                Button(action: {
                    submitAnswer()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(FontManager.geist(size: 24, weight: .medium))
                        .foregroundColor(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                        (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3)) :
                                        (colorScheme == .dark ? Color.blue : Color.blue))
                }
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.blue.opacity(0.1) : Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            // Auto-focus input after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
    }
    
    private func submitAnswer() {
        let answer = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !isSubmitting else { return }
        
        isSubmitting = true
        HapticManager.shared.selection()
        
        Task {
            await onAnswer(answer)
            
            await MainActor.run {
                isSubmitting = false
                answerText = ""
                isInputFocused = false
            }
        }
    }
}

// MARK: - Question Generator

struct ProactiveQuestionGenerator {
    /// Generate contextual question based on location visit
    static func generateQuestion(for locationName: String, isFirstVisit: Bool) -> String {
        if isFirstVisit {
            return "I noticed you're at \(locationName). What brings you here?"
        } else {
            // For returning visits, ask what they're getting
            return "I see you're at \(locationName) again. What are you getting today?"
        }
    }
}
