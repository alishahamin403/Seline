import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var feedbackService = FeedbackService.shared
    @StateObject private var themeManager = ThemeManager.shared

    @State private var feedbackMessage = ""
    @State private var isSubmitting = false

    private var isDarkMode: Bool {
        themeManager.getCurrentEffectiveColorScheme() == .dark
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Send Feedback")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isDarkMode ? .white : .black)

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(isDarkMode ? Color(UIColor.systemGray6).opacity(0.3) : Color(UIColor.systemGray6).opacity(0.5))

                ScrollView {
                    VStack(spacing: 16) {
                        // Description Text
                        Text("We'd love to hear from you! Tell us what you think about Seline.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                            .lineLimit(nil)

                        // Feedback TextEditor
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $feedbackMessage)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white : .black)
                                .scrollContentBackground(.hidden)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isDarkMode ? Color(UIColor.systemGray6).opacity(0.2) : Color(UIColor.systemGray6).opacity(0.3))
                                        .strokeBorder(
                                            isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                                .frame(minHeight: 120)

                            if feedbackMessage.isEmpty {
                                Text("Type your feedback here...")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }

                        // Character Count
                        HStack {
                            Spacer()
                            Text("\(feedbackMessage.count)/500")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.gray.opacity(0.6))
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }

                Divider()

                // Submit Button
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isDarkMode ? Color(UIColor.systemGray6).opacity(0.3) : Color(UIColor.systemGray6).opacity(0.5))
                            )
                    }

                    Button(action: submitFeedback) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Submit")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .background(feedbackMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting ? Color.gray : Color.blue)
                    .cornerRadius(8)
                    .disabled(feedbackMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(isDarkMode ? Color.gmailDarkBackground : Color.white)
        }
        .alert("Feedback Sent", isPresented: $feedbackService.feedbackSent) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for your feedback!")
        }
        .alert("Error", isPresented: $feedbackService.showError) {
            Button("OK") { }
        } message: {
            Text(feedbackService.errorMessage)
        }
    }

    private func submitFeedback() {
        isSubmitting = true
        Task {
            await feedbackService.sendFeedback(message: feedbackMessage)
            isSubmitting = false
        }
    }
}

#Preview {
    FeedbackView()
        .environmentObject(AuthenticationManager.shared)
}
