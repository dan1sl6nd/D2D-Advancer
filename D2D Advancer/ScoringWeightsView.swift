import SwiftUI

struct ScoringWeightsView: View {
    @ObservedObject private var preferences = TargetDemographicsPreferences.shared

    private var total: Double {
        preferences.weightIncome + preferences.weightDensity + preferences.weightHomeValue + preferences.weightConversion
    }

    private func normalized(_ value: Double) -> Double {
        guard total > 0 else { return 0.25 }
        return value / total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Color.electricViolet)
                Text("Scoring Weights")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    preferences.weightIncome = 0.30
                    preferences.weightDensity = 0.20
                    preferences.weightHomeValue = 0.25
                    preferences.weightConversion = 0.25
                }
                .font(.caption)
                .foregroundColor(Color.textSecondary)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 16) {
                // Stacked bar visualization
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.statusConverted)
                            .frame(width: geometry.size.width * normalized(preferences.weightIncome))
                        Rectangle()
                            .fill(Color.dataCyan)
                            .frame(width: geometry.size.width * normalized(preferences.weightDensity))
                        Rectangle()
                            .fill(Color.statusNotHome)
                            .frame(width: geometry.size.width * normalized(preferences.weightHomeValue))
                        Rectangle()
                            .fill(Color.electricViolet)
                            .frame(width: geometry.size.width * normalized(preferences.weightConversion))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 12)

                // Sliders
                weightSlider(label: "Income", icon: "dollarsign.circle", color: .statusConverted, value: $preferences.weightIncome)
                weightSlider(label: "Density", icon: "person.3", color: .dataCyan, value: $preferences.weightDensity)
                weightSlider(label: "Home Value", icon: "house", color: .statusNotHome, value: $preferences.weightHomeValue)
                weightSlider(label: "Conversion", icon: "chart.line.uptrend.xyaxis", color: .electricViolet, value: $preferences.weightConversion)

                // Live preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective Weights")
                        .font(.caption)
                        .foregroundColor(Color.textMuted)
                    HStack(spacing: 12) {
                        weightBadge("Inc", normalized(preferences.weightIncome), color: .statusConverted)
                        weightBadge("Den", normalized(preferences.weightDensity), color: .dataCyan)
                        weightBadge("Val", normalized(preferences.weightHomeValue), color: .statusNotHome)
                        weightBadge("Conv", normalized(preferences.weightConversion), color: .electricViolet)
                    }
                }
            }
            .padding(16)
            .background(Color.obsidianSurface)
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func weightSlider(label: String, icon: String, color: Color, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Text("\(Int(normalized(value.wrappedValue) * 100))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .tint(color)
        }
    }

    @ViewBuilder
    private func weightBadge(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
