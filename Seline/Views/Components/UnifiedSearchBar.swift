import SwiftUI

struct UnifiedSearchBar: View {
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    var placeholder: String
    var onCancel: () -> Void
    let colorScheme: ColorScheme
    var variant: AppAmbientBackgroundVariant = .topLeading

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.emailGlassMutedText(colorScheme))

                TextField(placeholder, text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .focused($isFocused)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 22)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: variant,
            cornerRadius: 24,
            highlightStrength: 0.75
        )
    }
}
