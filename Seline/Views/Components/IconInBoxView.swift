import SwiftUI

struct IconInBoxView: View {
    let systemName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .frame(width: 32, height: 32)

            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}
