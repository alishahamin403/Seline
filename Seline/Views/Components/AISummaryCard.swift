import SwiftUI

struct AISummaryCard: View {
    let summary: String
    @Environment(\.colorScheme) var colorScheme

    private var summaryBullets: [String] {
        // Split the summary into bullet points
        // For now, split by period and filter out empty strings
        return summary
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with AI icon and title
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.shadcnForeground(colorScheme))
                    .frame(width: 8, height: 8)

                Text("AI Summary")
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()
            }

            // Summary bullet points
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
        .padding(20)
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
    }
}

#Preview {
    VStack(spacing: 20) {
        AISummaryCard(summary: "Q4 marketing campaign exceeded targets by 23%, generating $2.4M in revenue. Social media engagement increased 45% with video content performing best. Budget allocation for Q1 needs approval by December 15th. Team recommends doubling investment in video marketing for next quarter.")

        AISummaryCard(summary: "Meeting scheduled for 2 PM tomorrow. Design review includes wireframes and prototypes. Stakeholder feedback to be discussed.")
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}