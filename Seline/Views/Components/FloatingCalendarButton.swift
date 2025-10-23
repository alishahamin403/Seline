import SwiftUI

struct FloatingCalendarButton: View {
    let onTap: () -> Void

    private var buttonColor: Color {
        Color(red: 0.92, green: 0.92, blue: 0.92)
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