import SwiftUI

/// Quick test view for DeepSeek integration
/// Add this to any view temporarily to test
struct DeepSeekTestView: View {
    @State private var testResult = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Text("DeepSeek Test")
                .font(.headline)

            Button("Test DeepSeek API") {
                testDeepSeek()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
            }

            if !testResult.isEmpty {
                ScrollView {
                    Text(testResult)
                        .font(.caption)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
    }

    func testDeepSeek() {
        isLoading = true
        testResult = ""

        Task {
            do {
                let response = try await DeepSeekService.shared.answerQuestion(
                    query: "Say 'DeepSeek is working!' in a creative way",
                    conversationHistory: [],
                    operationType: "test"
                )

                await MainActor.run {
                    testResult = "✅ SUCCESS!\n\nResponse: \(response)"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ ERROR:\n\n\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    DeepSeekTestView()
}
