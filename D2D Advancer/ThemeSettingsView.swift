import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject private var themeManager = CustomizableThemeManager.shared

    @State private var previewTitle = "Preview Card"
    @State private var previewSubtitle = "Buttons and cards reflect your theme"

    var body: some View {
        NavigationView {
            List {
                // Presets
                Section("Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            presetButton("Professional", theme: .professional)
                            presetButton("Modern", theme: .modern)
                            presetButton("Vibrant", theme: .vibrant)
                            presetButton("Minimal", theme: .minimal)
                            presetButton("Corporate", theme: .corporate)
                        }
                        .padding(.vertical, 4)
                    }
                    Button("Reset to Default") { themeManager.resetToDefault() }
                        .foregroundColor(.red)
                }

                // Colors
                Section("Colors") {
                    colorRow(title: "Primary", color: themeManager.currentTheme.primaryColor) { themeManager.setPrimaryColor($0) }
                    colorRow(title: "Secondary", color: themeManager.currentTheme.secondaryColor) { themeManager.setSecondaryColor($0) }
                    colorRow(title: "Accent", color: themeManager.currentTheme.accentColor) { themeManager.setAccentColor($0) }

                    colorRow(title: "Background", color: themeManager.currentTheme.backgroundColor) { themeManager.setBackgroundColor($0) }
                    colorRow(title: "Surface", color: themeManager.currentTheme.surfaceColor) { themeManager.setSurfaceColor($0) }

                    colorRow(title: "Text Primary", color: themeManager.currentTheme.textPrimaryColor) { themeManager.setTextPrimaryColor($0) }
                    colorRow(title: "Text Secondary", color: themeManager.currentTheme.textSecondaryColor) { themeManager.setTextSecondaryColor($0) }

                    colorRow(title: "Border", color: themeManager.currentTheme.borderColor) { themeManager.setBorderColor($0) }
                    colorRow(title: "Shadow", color: themeManager.currentTheme.shadowColor) { themeManager.setShadowColor($0) }

                    Button("Reset Colors Only") { themeManager.resetColorsOnly() }
                        .foregroundColor(.orange)
                }

                // Style
                Section("Style") {
                    sliderRow(
                        title: "Corner Radius",
                        value: Double(themeManager.currentTheme.cornerRadius),
                        range: 0...20
                    ) { new in themeManager.setCornerRadius(CGFloat(new)) }

                    sliderRow(
                        title: "Shadow Radius",
                        value: Double(themeManager.currentTheme.shadowRadius),
                        range: 0...15
                    ) { new in themeManager.setShadowRadius(CGFloat(new)) }

                    sliderRow(
                        title: "Button Padding",
                        value: Double(themeManager.currentTheme.buttonPadding),
                        range: 4...24
                    ) { new in themeManager.setButtonPadding(CGFloat(new)) }
                }

                // Preview
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(previewTitle)
                            .font(.headline)
                            .foregroundColor(Color.themeTextPrimary)
                        Text(previewSubtitle)
                            .font(.caption)
                            .foregroundColor(Color.themeTextSecondary)

                        HStack(spacing: 12) {
                            Button("Primary") {}
                                .customThemedButton(.primary)
                            Button("Secondary") {}
                                .customThemedButton(.secondary)
                            Button("Outline") {}
                                .customThemedButton(.outline)
                        }
                    }
                    .customThemedCard()
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func presetButton(_ title: String, theme: CustomizableTheme) -> some View {
        Button(action: { themeManager.loadPreset(theme) }) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.themeSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
                .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func colorRow(title: String, color: Color, onChange: @escaping (Color) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: Binding(get: { color }, set: onChange))
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func sliderRow(title: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))")
                    .foregroundColor(.secondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range)
        }
        .padding(.vertical, 2)
    }
}

