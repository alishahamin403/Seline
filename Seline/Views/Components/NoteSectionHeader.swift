import SwiftUI

struct NoteSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            if count > 0 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }
        }) {
            HStack {
                // Section title - matching email page font and size
                Text(title.lowercased().capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()

                // Count badge - black/white styling
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 0) {
        NoteSectionHeader(
            title: "PINNED",
            count: 3,
            isExpanded: .constant(true)
        )

        Rectangle()
            .fill(Color.white.opacity(0.3))
            .frame(height: 2)
            .padding(.vertical, 16)
            .padding(.horizontal, -20)

        NoteSectionHeader(
            title: "RECENT",
            count: 2,
            isExpanded: .constant(true)
        )
    }
    .padding(.horizontal, 20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}