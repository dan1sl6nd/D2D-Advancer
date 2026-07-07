import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage("isDarkMode") private var darkModeEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 34, height: 34)
                            .background(Color.electricViolet.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Dark Mode")
                            .font(.obsidianBody)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Toggle("Dark Mode", isOn: $darkModeEnabled)
                            .labelsHidden()
                            .accessibilityLabel("Dark Mode")
                            .accessibilityValue(darkModeEnabled ? "Enabled" : "Disabled")
                            .accessibilityHint("Toggles dark appearance for the app.")
                    }
                } header: {
                    Text("APPEARANCE")
                        .microLabel()
                }
                .obsidianListRow()

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Obsidian")
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                        Text("Premium dark theme with electric violet accents")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("ACTIVE THEME")
                        .microLabel()
                }
                .obsidianListRow()
            }
            .obsidianListScreen()
            .obsidianPushedNavigation("Theme", backButtonAccessibilityIdentifier: "themeSettingsBackButton")
        }
    }
}
