import SwiftUI

struct ThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDarkMode") private var darkModeEnabled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Theme",
                        subtitle: "Control the app appearance used across every screen.",
                        icon: "paintpalette.fill"
                    )

                    ObsidianSectionCard(
                        title: "Appearance",
                        icon: "moon.fill",
                        subtitle: "Switch between the light and dark app presentation."
                    ) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dark Mode")
                                    .font(.obsidianBody)
                                    .foregroundColor(Color.textPrimary)

                                Text(darkModeEnabled ? "Dark appearance is active." : "Light appearance is active.")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            Toggle("Dark Mode", isOn: $darkModeEnabled)
                                .labelsHidden()
                                .accessibilityLabel("Dark Mode")
                                .accessibilityValue(darkModeEnabled ? "Enabled" : "Disabled")
                                .accessibilityHint("Toggles dark appearance for the app.")
                        }
                        .padding(14)
                        .background(Color.obsidianElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                        )
                    }

                    ObsidianSectionCard(
                        title: "Active Theme",
                        icon: "sparkles",
                        subtitle: "Current visual system for buttons, cards, tabs, and forms."
                    ) {
                        HStack(spacing: 12) {
                            ObsidianIconTile(icon: "circle.hexagongrid.fill", tint: Color.electricViolet)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Obsidian")
                                    .font(.obsidianTitle)
                                    .foregroundColor(Color.textPrimary)

                                Text("Premium surfaces with electric violet accents.")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(Color.obsidianElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Theme",
                backButtonAccessibilityIdentifier: "themeSettingsBackButton",
                onBack: { dismiss() }
            )
        }
        .obsidianModalBackground()
    }
}
