import SwiftUI

struct HalfCircleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2

        // Create half circle arc from left to right (180 degrees)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )

        return path
    }
}

struct HalfCircleOutlineView: View {
    @Environment(\.colorScheme) var colorScheme

    private var strokeColor: Color {
        if colorScheme == .dark {
            return Color.white
        } else {
            return Color.gray
        }
    }

    var body: some View {
        HalfCircleOutline()
            .stroke(strokeColor, lineWidth: 0.5)
            .frame(width: 180, height: 90)
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Half Circle Preview")
            .font(.title2)

        HalfCircleOutlineView()

        // Preview with different background colors
        HalfCircleOutlineView()
            .background(Color.gray.opacity(0.1))
    }
    .padding()
}