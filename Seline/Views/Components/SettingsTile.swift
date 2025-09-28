import SwiftUI

struct SettingsTile<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.getCurrentEffectiveColorScheme(systemColorScheme: colorScheme) == .dark
    }

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.shadcnTextBase)
                .foregroundColor(isDarkMode ? Color.shadcnForeground(.dark) : Color.shadcnForeground(.light))

            Spacer()

            trailing()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(isDarkMode ? Color.black : Color.white)
        )
        .shadow(
            color: isDarkMode ? .white.opacity(0.08) : .gray.opacity(0.15),
            radius: isDarkMode ? 8 : 12,
            x: 0,
            y: isDarkMode ? 3 : 4
        )
        .shadow(
            color: isDarkMode ? .white.opacity(0.04) : .gray.opacity(0.08),
            radius: isDarkMode ? 4 : 6,
            x: 0,
            y: isDarkMode ? 1 : 2
        )
        .shadow(
            color: isDarkMode ? .white.opacity(0.02) : .clear,
            radius: isDarkMode ? 8 : 0,
            x: 0,
            y: isDarkMode ? 2 : 0
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        SettingsTile(title: "Notifications") {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
        }

        SettingsTile(title: "Language") {
            Text("English")
                .font(.shadcnTextSm)
                .foregroundColor(.gray)
        }

        SettingsTile(title: "Night mode") {
            Toggle("", isOn: .constant(false))
                .labelsHidden()
        }
    }
    .padding()
}