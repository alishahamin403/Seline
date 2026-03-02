import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var feedbackService = FeedbackService.shared
    @ObservedObject var themeManager = ThemeManager.shared

    @State private var feedbackMessage = ""
    @State private var isSubmitting = false

    private var isDarkMode: Bool {
        themeManager.effectiveColorScheme == .dark
    }

    private var resolvedColorScheme: ColorScheme {
        isDarkMode ? .dark : .light
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppAmbientBackgroundLayer(colorScheme: resolvedColorScheme, variant: .topLeading)

                VStack(spacing: 12) {
                    HStack {
                        Text("Send Feedback")
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(isDarkMode ? .white : .black)

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(FontManager.geist(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .appAmbientCardStyle(
                        colorScheme: resolvedColorScheme,
                        variant: .topTrailing,
                        cornerRadius: 24,
                        highlightStrength: 0.62
                    )

                    ScrollView {
                        VStack(spacing: 16) {
                            Text("We'd love to hear from you. Tell us what is working, what feels rough, or what you want next.")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.68) : .black.opacity(0.56))
                                .lineLimit(nil)

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $feedbackMessage)
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white : .black)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 140)
                                    .padding(4)
                                    .appAmbientInnerSurfaceStyle(
                                        colorScheme: resolvedColorScheme,
                                        cornerRadius: 16
                                    )

                                if feedbackMessage.isEmpty {
                                    Text("Type your feedback here...")
                                        .font(FontManager.geist(size: 16, weight: .regular))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }

                            HStack {
                                Spacer()
                                Text("\(feedbackMessage.count)/500")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }
                        .padding(20)
                        .appAmbientCardStyle(
                            colorScheme: resolvedColorScheme,
                            variant: .bottomTrailing,
                            cornerRadius: 28,
                            highlightStrength: 0.58
                        )
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 12)

                    HStack(spacing: 12) {
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(FontManager.geist(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .appAmbientInnerSurfaceStyle(
                            colorScheme: resolvedColorScheme,
                            cornerRadius: 16
                        )

                        Button(action: submitFeedback) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                Text("Submit")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(feedbackMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting ? Color.gray.opacity(0.75) : Color.black.opacity(isDarkMode ? 0.92 : 0.84))
                        )
                        .disabled(feedbackMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
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
