import SwiftUI

struct StraightLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Create a horizontal straight line from left to right
        let startPoint = CGPoint(x: 0, y: rect.midY)
        let endPoint = CGPoint(x: rect.width, y: rect.midY)

        path.move(to: startPoint)
        path.addLine(to: endPoint)

        return path
    }
}

struct StraightLineView: View {
    @Environment(\.colorScheme) var colorScheme

    private var strokeColor: Color {
        if colorScheme == .dark {
            return Color.white
        } else {
            return Color.gray
        }
    }

    var body: some View {
        StraightLine()
            .stroke(strokeColor, lineWidth: 0.5)
            .frame(width: 180, height: 40)
            .shadcnShadow()
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Straight Line Preview")
            .font(.title2)

        StraightLineView()

        // Preview with different background colors
        StraightLineView()
            .background(Color.gray.opacity(0.1))
    }
    .padding()
}