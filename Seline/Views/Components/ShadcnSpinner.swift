import SwiftUI

/// A shadcn-inspired spinner component for loading states
/// Based on https://ui.shadcn.com/docs/components/spinner
struct ShadcnSpinner: View {
    @Environment(\.colorScheme) var colorScheme

    enum Size {
        case small      // 16x16
        case medium     // 20x20
        case large      // 24x24
        case extraLarge // 32x32

        var dimension: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            case .extraLarge: return 32
            }
        }

        var strokeWidth: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 2.5
            case .large: return 3
            case .extraLarge: return 3.5
            }
        }
    }

    let size: Size
    let color: Color?

    init(size: Size = .medium, color: Color? = nil) {
        self.size = size
        self.color = color
    }

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                color ?? (colorScheme == .dark ? .white : .black),
                style: StrokeStyle(
                    lineWidth: size.strokeWidth,
                    lineCap: .round
                )
            )
            .frame(width: size.dimension, height: size.dimension)
            .rotationEffect(.degrees(-90))
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
            .modifier(SpinningAnimation())
    }
}

/// Animation modifier for continuous spinning
private struct SpinningAnimation: ViewModifier {
    @State private var isRotating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                Animation.linear(duration: 1)
                    .repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear {
                isRotating = true
            }
    }
}

/// Loading view with spinner and optional text
struct LoadingView: View {
    @Environment(\.colorScheme) var colorScheme

    let text: String
    let spinnerSize: ShadcnSpinner.Size
    let spacing: CGFloat

    init(
        text: String = "Loading...",
        spinnerSize: ShadcnSpinner.Size = .medium,
        spacing: CGFloat = 12
    ) {
        self.text = text
        self.spinnerSize = spinnerSize
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ShadcnSpinner(size: spinnerSize)

            Text(text)
                .font(FontManager.geist(size: .body, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

/// Centered loading overlay for full-screen loading states
struct LoadingOverlay: View {
    @Environment(\.colorScheme) var colorScheme

    let text: String
    let spinnerSize: ShadcnSpinner.Size

    init(
        text: String = "Loading...",
        spinnerSize: ShadcnSpinner.Size = .large
    ) {
        self.text = text
        self.spinnerSize = spinnerSize
    }

    var body: some View {
        VStack(spacing: 16) {
            ShadcnSpinner(size: spinnerSize)

            if !text.isEmpty {
                Text(text)
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.shadcnBackground(colorScheme).opacity(0.8))
    }
}

// MARK: - Previews

#Preview("Spinner Sizes") {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            VStack {
                ShadcnSpinner(size: .small)
                Text("Small")
                    .font(.caption)
            }

            VStack {
                ShadcnSpinner(size: .medium)
                Text("Medium")
                    .font(.caption)
            }

            VStack {
                ShadcnSpinner(size: .large)
                Text("Large")
                    .font(.caption)
            }

            VStack {
                ShadcnSpinner(size: .extraLarge)
                Text("Extra Large")
                    .font(.caption)
            }
        }

        Divider()

        VStack(spacing: 16) {
            Text("Custom Colors")
                .font(.headline)

            HStack(spacing: 20) {
                ShadcnSpinner(size: .large, color: .blue)
                ShadcnSpinner(size: .large, color: .green)
                ShadcnSpinner(size: .large, color: .red)
                ShadcnSpinner(size: .large, color: .orange)
            }
        }
    }
    .padding()
}

#Preview("Loading View") {
    VStack(spacing: 32) {
        LoadingView(text: "Generating AI summary...")
        LoadingView(text: "Fetching emails...", spinnerSize: .large)
        LoadingView(text: "Saving...", spinnerSize: .small, spacing: 8)
    }
    .padding()
}

#Preview("Loading Overlay") {
    LoadingOverlay(text: "Loading your content...")
}

#Preview("Dark Mode") {
    VStack(spacing: 24) {
        ShadcnSpinner(size: .large)
        LoadingView(text: "Loading...")
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
