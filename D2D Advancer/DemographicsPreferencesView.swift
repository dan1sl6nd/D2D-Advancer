import SwiftUI

struct DemographicsPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = TargetDemographicsPreferences.shared
    @State private var showingCustomIncome = false
    @State private var showingCustomHomeValue = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Demographics")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Configure your ideal customer profile to get better area recommendations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Preset Profiles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Profiles")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(TargetDemographicsPreferences.TargetProfile.allCases, id: \.self) { profile in
                                    ProfileCard(
                                        profile: profile,
                                        isSelected: preferences.selectedProfile == profile,
                                        onTap: {
                                            preferences.applyProfile(profile)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Income Range
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.green)
                            Text("Target Income Range")
                                .font(.headline)
                        }
                        .padding(.horizontal, 20)

                        VStack(spacing: 16) {
                            HStack {
                                Text("Min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetIncomeMin, in: 20000...300000, step: 10000)

                                Text(formatCurrency(preferences.targetIncomeMin))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 80, alignment: .trailing)
                            }

                            HStack {
                                Text("Max")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetIncomeMax, in: 30000...500000, step: 10000)

                                Text(formatCurrency(preferences.targetIncomeMax))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                        .padding(16)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }

                    // Home Value Range
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "house.circle.fill")
                                .foregroundColor(.blue)
                            Text("Target Home Value Range")
                                .font(.headline)
                        }
                        .padding(.horizontal, 20)

                        VStack(spacing: 16) {
                            HStack {
                                Text("Min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetHomeValueMin, in: 50000...1000000, step: 25000)

                                Text(formatCurrency(preferences.targetHomeValueMin))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 90, alignment: .trailing)
                            }

                            HStack {
                                Text("Max")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetHomeValueMax, in: 100000...2000000, step: 50000)

                                Text(formatCurrency(preferences.targetHomeValueMax))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                        .padding(16)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }

                    // Homeownership Preference
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(.orange)
                            Text("Homeownership")
                                .font(.headline)
                        }
                        .padding(.horizontal, 20)

                        Toggle("Prefer Homeowners", isOn: $preferences.preferHomeowners)
                            .padding(16)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 80)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Reset") {
                        preferences.resetToDefaults()
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)

                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else {
            return String(format: "$%.0fk", value / 1_000)
        }
    }
}

struct ProfileCard: View {
    let profile: TargetDemographicsPreferences.TargetProfile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: profileIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    )

                Text(profile.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(height: 34)

                Text(profile.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(height: 45)
            }
            .frame(width: 140)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var profileIcon: String {
        switch profile {
        case .solarPanels:
            return "sun.max.fill"
        case .roofing:
            return "house.fill"
        case .hvac:
            return "fan.fill"
        case .windows:
            return "rectangle.on.rectangle.angled"
        case .landscaping:
            return "leaf.fill"
        case .remodeling:
            return "hammer.fill"
        case .security:
            return "lock.shield.fill"
        case .pools:
            return "drop.fill"
        case .torontoGeneral:
            return "building.2.fill"
        case .torontoPremium:
            return "crown.fill"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

#Preview {
    DemographicsPreferencesView()
}