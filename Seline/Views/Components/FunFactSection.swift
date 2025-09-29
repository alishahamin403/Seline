import SwiftUI

struct FunFactSection: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var funFactsService = FunFactsService.shared
    @State private var isExpanded: Bool = true // Expanded by default

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FUN FACT header - tappable to expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("FUN FACT")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    if funFactsService.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            // Fun fact content - only show when expanded
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(funFactsService.currentFact)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.clear)
    }
}

#Preview {
    VStack(spacing: 16) {
        FunFactSection()
    }
    .padding(.horizontal, 20)
    .background(Color.shadcnBackground(.light))
}