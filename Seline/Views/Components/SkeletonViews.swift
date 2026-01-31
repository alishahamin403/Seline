import SwiftUI

// MARK: - Skeleton Loading Views
// Modern skeleton screens with pulsing animation for better perceived performance

/// Reusable pulsing animation modifier
struct PulsingAnimation: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

extension View {
    func skeletonPulsing() -> some View {
        self.modifier(PulsingAnimation())
    }
}

// MARK: - Email List Skeleton

struct EmailListSkeleton: View {
    let itemCount: Int
    @Environment(\.colorScheme) var colorScheme

    init(itemCount: Int = 5) {
        self.itemCount = itemCount
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<itemCount, id: \.self) { index in
                EmailRowSkeleton()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

struct EmailRowSkeleton: View {
    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var skeletonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture skeleton
            Circle()
                .fill(skeletonColor)
                .frame(width: 44, height: 44)
                .skeletonPulsing()

            VStack(alignment: .leading, spacing: 8) {
                // Sender name skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 140, height: 14)
                    .skeletonPulsing()

                // Subject line skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 220, height: 12)
                    .skeletonPulsing()

                // Snippet skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 180, height: 10)
                    .skeletonPulsing()
            }

            Spacer()

            // Time skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 60, height: 10)
                .skeletonPulsing()
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Notes List Skeleton

struct NotesListSkeleton: View {
    let itemCount: Int
    @Environment(\.colorScheme) var colorScheme

    init(itemCount: Int = 6) {
        self.itemCount = itemCount
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(0..<itemCount, id: \.self) { index in
                NoteCardSkeleton()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

struct NoteCardSkeleton: View {
    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var skeletonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(height: 16)
                .frame(maxWidth: .infinity)
                .skeletonPulsing()

            // Content lines skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(skeletonColor)
                    .frame(height: 12)
                    .skeletonPulsing()

                RoundedRectangle(cornerRadius: 3)
                    .fill(skeletonColor)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: 160)
                    .skeletonPulsing()
            }

            Spacer()

            // Date skeleton
            RoundedRectangle(cornerRadius: 3)
                .fill(skeletonColor)
                .frame(width: 80, height: 10)
                .skeletonPulsing()
        }
        .padding(14)
        .frame(height: 140)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Calendar Events Skeleton

struct CalendarEventsSkeleton: View {
    let itemCount: Int
    @Environment(\.colorScheme) var colorScheme

    init(itemCount: Int = 4) {
        self.itemCount = itemCount
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<itemCount, id: \.self) { index in
                CalendarEventRowSkeleton()
                    .transition(.opacity.combined(with: .slide))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct CalendarEventRowSkeleton: View {
    @Environment(\.colorScheme) var colorScheme

    private var skeletonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Time skeleton
            VStack(alignment: .trailing, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(skeletonColor)
                    .frame(width: 50, height: 12)
                    .skeletonPulsing()

                RoundedRectangle(cornerRadius: 3)
                    .fill(skeletonColor)
                    .frame(width: 40, height: 10)
                    .skeletonPulsing()
            }

            // Event card skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(height: 14)
                    .frame(maxWidth: 180, alignment: .leading)
                    .skeletonPulsing()

                RoundedRectangle(cornerRadius: 3)
                    .fill(skeletonColor)
                    .frame(height: 10)
                    .frame(maxWidth: 120, alignment: .leading)
                    .skeletonPulsing()
            }

            Spacer()

            // Icon skeleton
            Circle()
                .fill(skeletonColor)
                .frame(width: 24, height: 24)
                .skeletonPulsing()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Receipt Stats Skeleton

struct ReceiptStatsSkeleton: View {
    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var skeletonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 120, height: 20)
                    .skeletonPulsing()

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 80, height: 16)
                    .skeletonPulsing()
            }

            // Stats grid skeleton
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skeletonColor)
                            .frame(height: 24)
                            .skeletonPulsing()

                        RoundedRectangle(cornerRadius: 3)
                            .fill(skeletonColor)
                            .frame(height: 12)
                            .skeletonPulsing()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // Chart skeleton
            RoundedRectangle(cornerRadius: 8)
                .fill(skeletonColor)
                .frame(height: 200)
                .skeletonPulsing()
        }
        .padding(20)
    }
}

// MARK: - Location Card Skeleton

struct LocationCardSkeleton: View {
    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var skeletonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Icon skeleton
                Circle()
                    .fill(skeletonColor)
                    .frame(width: 40, height: 40)
                    .skeletonPulsing()

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(skeletonColor)
                        .frame(width: 140, height: 16)
                        .skeletonPulsing()

                    RoundedRectangle(cornerRadius: 3)
                        .fill(skeletonColor)
                        .frame(width: 200, height: 12)
                        .skeletonPulsing()
                }

                Spacer()
            }

            // Visit info skeleton
            HStack(spacing: 16) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(skeletonColor)
                            .frame(width: 60, height: 10)
                            .skeletonPulsing()

                        RoundedRectangle(cornerRadius: 3)
                            .fill(skeletonColor)
                            .frame(width: 40, height: 14)
                            .skeletonPulsing()
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview("Email Skeleton") {
    ScrollView {
        EmailListSkeleton()
    }
    .background(Color.shadcnBackground(.light))
}

#Preview("Notes Skeleton") {
    ScrollView {
        NotesListSkeleton()
    }
    .background(Color.shadcnBackground(.light))
}

#Preview("Calendar Skeleton") {
    ScrollView {
        CalendarEventsSkeleton()
    }
    .background(Color.shadcnBackground(.light))
}

#Preview("Receipt Stats Skeleton") {
    ScrollView {
        ReceiptStatsSkeleton()
    }
    .background(Color.shadcnBackground(.light))
}
