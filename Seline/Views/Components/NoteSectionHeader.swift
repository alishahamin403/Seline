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
            HStack(spacing: 6) {
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(headerSecondaryColor)
                    .textCase(.uppercase)
                    .tracking(0.6)

                if count > 0 {
                    Text("· \(count)")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(headerSecondaryColor)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var headerSecondaryColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
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
