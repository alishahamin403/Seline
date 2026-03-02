import SwiftUI

struct VisitReasonPopupCard: View {
    let place: SavedPlace
    let visit: LocationVisitRecord
    let colorScheme: ColorScheme
    let onSave: (String) async -> Void
    let onDismiss: () -> Void

    @State private var reasonText: String = ""
    @FocusState private var isFocused: Bool
    @State private var isSubmitting = false

    init(place: SavedPlace, visit: LocationVisitRecord, colorScheme: ColorScheme, onSave: @escaping (String) async -> Void, onDismiss: @escaping () -> Void) {
        self.place = place
        self.visit = visit
        self.colorScheme = colorScheme
        self.onSave = onSave
        self.onDismiss = onDismiss
        _reasonText = State(initialValue: visit.visitNotes ?? "")
    }

    var body: some View {
        cardContent
            .padding(16)
            .homeGlassCardStyle(colorScheme: colorScheme, cornerRadius: 18, highlightStrength: 0.95)
            .padding(.horizontal, 12)
    }

    // MARK: - Subviews

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            questionPrompt
            inputSection
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            locationInfo
            Spacer()
            dismissButton
        }
    }

    private var locationInfo: some View {
        Text(place.displayName)
            .font(FontManager.geist(size: 18, weight: .semibold))
            .foregroundColor(primaryTextColor)
            .lineLimit(1)
    }

    private var dismissButton: some View {
        Button(action: {
            HapticManager.shared.light()
            onDismiss()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(dismissButtonColor)
                .padding(8)
                .background(
                    Circle()
                        .fill(dismissButtonBackground)
                )
        }
    }

    private var questionPrompt: some View {
        Text("What brings you here?")
            .font(FontManager.geist(size: 14, weight: .medium))
            .foregroundColor(promptTextColor)
    }

    private var inputSection: some View {
        HStack(spacing: 8) {
            textField
            if hasText {
                submitButton
            }
        }
        .padding(12)
        .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 12)
        .animation(.easeInOut(duration: 0.2), value: reasonText.isEmpty)
    }

    private var textField: some View {
        TextField("e.g., picking up groceries, meeting a friend...", text: $reasonText, axis: .vertical)
            .font(FontManager.geist(size: 14, weight: .regular))
            .foregroundColor(primaryTextColor)
            .lineLimit(1...3)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit {
                if hasText {
                    submitReason()
                }
            }
    }

    private var submitButton: some View {
        Button(action: submitReason) {
            submitButtonContent
        }
        .disabled(isSubmitting)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var submitButtonContent: some View {
        if isSubmitting {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.black)
        } else {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
        }
    }

    // MARK: - Styling Helpers

    private var hasText: Bool {
        !reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
    }

    private var promptTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8)
    }

    private var dismissButtonColor: Color {
        colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)
    }

    private var dismissButtonBackground: Color {
        Color.homeGlassInnerTint(colorScheme)
    }

    // MARK: - Actions

    private func submitReason() {
        let trimmedReason = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { return }

        isSubmitting = true
        HapticManager.shared.success()
        isFocused = false

        Task {
            await onSave(trimmedReason)
            await MainActor.run {
                isSubmitting = false
            }
        }
    }
}

#Preview {
    VStack {
        VisitReasonPopupCard(
            place: SavedPlace(
                googlePlaceId: "test",
                name: "Home",
                address: "123 Main St",
                latitude: 0,
                longitude: 0
            ),
            visit: LocationVisitRecord.create(
                userId: UUID(),
                savedPlaceId: UUID(),
                entryTime: Date()
            ),
            colorScheme: .light,
            onSave: { _ in },
            onDismiss: { }
        )

        Spacer()
    }
    .padding(.top, 20)
    .background(Color.white)
}
