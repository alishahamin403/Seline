import SwiftUI

enum BadgeVariant {
    case primary
    case success
    case destructive
    case secondary
    case outline
    case count

    func backgroundColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary:
            return colorScheme == .dark ?
                Color.white :
                Color.black
        case .success:
            return colorScheme == .dark ?
                Color.green.opacity(0.2) :
                Color.green.opacity(0.15)
        case .destructive:
            return colorScheme == .dark ?
                Color.red.opacity(0.2) :
                Color.red.opacity(0.15)
        case .secondary:
            return colorScheme == .dark ?
                Color.white.opacity(0.1) :
                Color.black.opacity(0.05)
        case .outline:
            return .clear
        case .count:
            return colorScheme == .dark ?
                Color.white.opacity(0.15) :
                Color.black.opacity(0.08)
        }
    }

    func foregroundColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary:
            return .white
        case .success:
            return colorScheme == .dark ?
                Color.green.opacity(0.9) :
                Color.green.opacity(0.8)
        case .destructive:
            return colorScheme == .dark ?
                Color.red.opacity(0.9) :
                Color.red.opacity(0.8)
        case .secondary:
            return colorScheme == .dark ? .white : .black
        case .outline:
            return colorScheme == .dark ? .white : .black
        case .count:
            return colorScheme == .dark ? .white : .black
        }
    }

    func borderColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .outline:
            return colorScheme == .dark ?
                Color.white.opacity(0.2) :
                Color.black.opacity(0.2)
        default:
            return .clear
        }
    }
}

struct ShadcnBadge: View {
    let text: String
    let variant: BadgeVariant
    @Environment(\.colorScheme) var colorScheme

    init(_ text: String, variant: BadgeVariant = .secondary) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(variant.foregroundColor(colorScheme: colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(variant.backgroundColor(colorScheme: colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(variant.borderColor(colorScheme: colorScheme), lineWidth: variant == .outline ? 1 : 0)
            )
    }
}
