import SwiftUI

struct FloatingCalendarButton: View {
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var buttonColor: Color {
        Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "calendar")
                .font(FontManager.geist(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(buttonColor)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack {
        Spacer()
        HStack {
            Spacer()
            FloatingCalendarButton(onTap: {})
                .padding(.trailing, 20)
                .padding(.bottom, 60)
        }
    }
    .background(Color.shadcnBackground(.light))
}