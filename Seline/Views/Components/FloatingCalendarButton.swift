import SwiftUI

struct FloatingCalendarButton: View {
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var buttonColor: Color {
        colorScheme == .dark ?
            Color(red: 0.1, green: 0.1, blue: 0.1) :      // #1a1a1a
            Color(red: 0.29, green: 0.29, blue: 0.29)     // #4a4a4a
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
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