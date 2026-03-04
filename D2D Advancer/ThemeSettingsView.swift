import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage("isDarkMode") private var darkModeEnabled = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 28)
                        Text("Dark Mode")
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Toggle("", isOn: $darkModeEnabled)
                    }
                } header: {
                    Text("APPEARANCE")
                        .font(.system(size: 11, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundColor(Color.textMuted)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Obsidian")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                        Text("Premium dark theme with electric violet accents")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.textSecondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("ACTIVE THEME")
                        .font(.system(size: 11, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundColor(Color.textMuted)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.obsidianBlack)
        }
    }
}
