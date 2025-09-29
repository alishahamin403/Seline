import SwiftUI

enum AISummaryState {
    case collapsed
    case loading
    case loaded(String)
    case error(String)
}

struct AISummaryCard: View {
    @State private var summaryState: AISummaryState = .collapsed
    let email: Email
    let onGenerateSummary: (Email) async -> Result<String, Error>
    @Environment(\.colorScheme) var colorScheme

    private var summaryBullets: [String] {
        switch summaryState {
        case .loaded(let summary):
            // Split the summary into bullet points
            return summary
                .components(separatedBy: ". ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header - always visible, no bullet point
            HStack(spacing: 12) {
                Text("AI Summary")
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Content - always shown
            VStack(alignment: .leading, spacing: 16) {
                switch summaryState {
                case .collapsed:
                    loadingView

                case .loading:
                    loadingView

                case .loaded:
                    summaryContentView

                case .error(let errorMessage):
                    errorView(errorMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 8 : 12,
            x: 0,
            y: colorScheme == .dark ? 3 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.04) : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 6,
            x: 0,
            y: colorScheme == .dark ? 1 : 2
        )
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.02) : .clear,
            radius: colorScheme == .dark ? 8 : 0,
            x: 0,
            y: colorScheme == .dark ? 2 : 0
        )
        .onAppear {
            // If we already have a summary, show it immediately
            if let existingSummary = email.aiSummary {
                summaryState = .loaded(existingSummary)
            } else {
                // Automatically start generating summary when view appears
                Task {
                    await generateSummary()
                }
            }
        }
    }

    // MARK: - View Components

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(Color.shadcnMuted(colorScheme))

            Text("Generating AI summary...")
                .font(FontManager.geist(size: .body, weight: .regular))
                .foregroundColor(Color.shadcnMuted(colorScheme))

            Spacer()
        }
        .padding(.vertical, 16)
    }

    private var summaryContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(summaryBullets.enumerated()), id: \.offset) { index, bullet in
                HStack(alignment: .top, spacing: 12) {
                    // Bullet point
                    Circle()
                        .fill(Color.shadcnForeground(colorScheme))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    // Bullet text
                    Text(bullet)
                        .font(FontManager.geist(size: .body, weight: .regular))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func errorView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)

                Text("Failed to generate summary")
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(.red)
            }

            Text(errorMessage)
                .font(FontManager.geist(size: .caption, weight: .regular))
                .foregroundColor(Color.shadcnMuted(colorScheme))

            Button(action: {
                Task {
                    await generateSummary()
                }
            }) {
                Text("Try Again")
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(Color.shadcnPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnRadius.md)
                            .stroke(Color.shadcnPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func generateSummary() async {
        summaryState = .loading

        let result = await onGenerateSummary(email)

        await MainActor.run {
            switch result {
            case .success(let summary):
                summaryState = .loaded(summary)
            case .failure(let error):
                summaryState = .error(error.localizedDescription)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AISummaryCard(
            email: Email.sampleEmails[0],
            onGenerateSummary: { email in
                // Mock function for preview
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    return .success("Q4 marketing campaign exceeded targets by 23%, generating $2.4M in revenue. Social media engagement increased 45% with video content performing best. Budget allocation for Q1 needs approval by December 15th. Team recommends doubling investment in video marketing for next quarter.")
                } catch {
                    return .failure(error)
                }
            }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}