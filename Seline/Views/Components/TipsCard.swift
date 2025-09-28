import SwiftUI

struct TipsCard: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var funFactsService = FunFactsService.shared

    // Blue theme colors for lightbulb (matching bottom tab bar)
    private var lightbulbColor: Color {
        if colorScheme == .dark {
            // Light blue for dark mode - #84cae9
            return Color(red: 0.518, green: 0.792, blue: 0.914)
        } else {
            // Dark blue for light mode - #345766
            return Color(red: 0.20, green: 0.34, blue: 0.40)
        }
    }


    var body: some View {
        HStack(spacing: 16) {
            // Lightbulb icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(lightbulbColor)

            // Tip text
            Text(funFactsService.currentFact)
                .font(.shadcnTextXs)
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 0 : 12,
            x: 0,
            y: colorScheme == .dark ? 0 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 0 : 6,
            x: 0,
            y: colorScheme == .dark ? 0 : 2
        )
        .padding(.horizontal, 20)
        .onAppear {
            // Service automatically handles 3-hour refresh cycle
        }
    }
}

#Preview {
    TipsCard()
}