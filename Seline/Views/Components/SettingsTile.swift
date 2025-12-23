import SwiftUI

struct SettingsTile<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing
    @ObservedObject var themeManager = ThemeManager.shared

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.effectiveColorScheme == .dark
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
        .shadcnTileStyle(colorScheme: themeManager.effectiveColorScheme ?? .light)
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