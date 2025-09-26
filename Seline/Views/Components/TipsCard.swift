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
        .padding(.horizontal, 20)
        .onTapGesture {
            // Manually refresh fact on tap
            withAnimation(.easeInOut(duration: 0.3)) {
                funFactsService.manualRefresh()
            }
        }
        .onAppear {
            // Service automatically handles 3-hour refresh cycle
            // Tap to refresh manually for immediate new fact
        }
    }
}

#Preview {
    TipsCard()
}