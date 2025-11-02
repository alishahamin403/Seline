import SwiftUI

struct ShadcnToggleGroup: View {
    @Binding var selection: String
    let options: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = option
                        HapticManager.shared.selection()
                    }
                }) {
                    Text(option)
                        .font(.system(size: 14, weight: selection == option ? .semibold : .regular))
                        .foregroundColor(
                            selection == option ?
                                (colorScheme == .dark ?
                                    Color.white :
                                    Color.black) :
                                (colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selection == option ?
                                        (colorScheme == .dark ?
                                            Color.white.opacity(0.1) :
                                            Color.black.opacity(0.05)) :
                                        Color.clear
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.black.opacity(0.03)
                )
        )
    }
}
