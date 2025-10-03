import SwiftUI

struct FunFactSection: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var funFactsService = FunFactsService.shared

    var body: some View {
        HStack(alignment: .center, spacing: ShadcnSpacing.sm) {
            // Fun fact content centered - limited to 2 lines
            Text(funFactsService.currentFact)
                .font(.shadcnTextSm)
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if funFactsService.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, ShadcnSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
    }
}

#Preview {
    VStack(spacing: 16) {
        FunFactSection()
    }
    .padding(.horizontal, 20)
    .background(Color.shadcnBackground(.light))
}