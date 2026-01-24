import SwiftUI

/// View showing progress during Gmail label import
struct LabelImportProgressView: View {
    @ObservedObject var progress: ImportProgress
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Importing Your Gmail Labels")
                    .font(FontManager.geist(size: .title2, weight: .semibold))

                Text("Setting up your email folders from Gmail...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Animated icon
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: progress.progressPercentage)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: progress.progressPercentage)

                    Image(systemName: "envelope.badge")
                        .font(FontManager.geist(size: 24, weight: .regular))
                        .foregroundColor(.blue)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                }

                // Progress percentage
                Text("\(Int(progress.progressPercentage * 100))%")
                    .font(FontManager.geist(size: .body, weight: .semibold))
                    .foregroundColor(.blue)
            }

            Spacer()

            // Status message
            VStack(spacing: 8) {
                Text(progress.phase)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if progress.total > 0 {
                    Text("\(progress.current) of \(progress.total) labels")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            ProgressView(value: progress.progressPercentage)
                .tint(.blue)
                .frame(height: 4)

            Spacer()

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .opacity(progress.isImporting ? 1 : 0)
                    .scaleEffect(progress.isImporting ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: progress.isImporting)

                Text(progress.isImporting ? "Importing..." : "Ready")
                    .font(.caption)
                    .foregroundColor(progress.isImporting ? .green : .secondary)

                Spacer()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview {
    @State var progress = ImportProgress()

    return ZStack {
        Color(.systemBackground).ignoresSafeArea()

        LabelImportProgressView(progress: progress)
            .onAppear {
                // Simulate progress
                Task {
                    for i in 0...10 {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        await progress.updateProgress(phase: "Importing labels", current: i, total: 10)
                    }
                    await progress.updateProgress(phase: "Complete", current: 10, total: 10)
                }
            }
    }
}
