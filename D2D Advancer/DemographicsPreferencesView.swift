import SwiftUI

struct DemographicsPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = TargetDemographicsPreferences.shared
    @State private var showingCustomIncome = false
    @State private var showingCustomHomeValue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Target Demographics",
                        subtitle: "Set the customer profile used for area recommendations.",
                        icon: "person.2.crop.square.stack.fill"
                    )

                    LeadFormSectionCard(title: "Quick Profiles", icon: "person.2.crop.square.stack.fill") {
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
                            .padding(.horizontal, 2)
                        }
                    }

                    LeadFormSectionCard(title: "Target Income Range", icon: "dollarsign.circle.fill") {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Min")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetIncomeMin, in: 20000...300000, step: 10000)

                                Text(formatCurrency(preferences.targetIncomeMin))
                                    .font(.obsidianFootnote)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 80, alignment: .trailing)
                            }

                            HStack {
                                Text("Max")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetIncomeMax, in: 30000...500000, step: 10000)

                                Text(formatCurrency(preferences.targetIncomeMax))
                                    .font(.obsidianFootnote)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                    }

                    LeadFormSectionCard(title: "Target Home Value Range", icon: "house.circle.fill") {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Min")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetHomeValueMin, in: 50000...1000000, step: 25000)

                                Text(formatCurrency(preferences.targetHomeValueMin))
                                    .font(.obsidianFootnote)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 90, alignment: .trailing)
                            }

                            HStack {
                                Text("Max")
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 50, alignment: .leading)

                                Slider(value: $preferences.targetHomeValueMax, in: 100000...2000000, step: 50000)

                                Text(formatCurrency(preferences.targetHomeValueMax))
                                    .font(.obsidianFootnote)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                    }

                    LeadFormSectionCard(title: "Homeownership", icon: "person.crop.circle.fill") {
                        Toggle("Prefer Homeowners", isOn: $preferences.preferHomeowners)
                            .font(.obsidianBody)
                            .foregroundColor(.textPrimary)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Target Demographics",
                backButtonAccessibilityIdentifier: "demographicsPreferencesBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    primaryAction: {
                        dismiss()
                    },
                    secondaryAction: {
                        preferences.resetToDefaults()
                    },
                    primaryLabel: {
                        Label("Done", systemImage: "checkmark")
                    },
                    secondaryLabel: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                )
            }
        }
        .obsidianModalBackground()
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
                    .font(.obsidianAction)
                    .foregroundColor(isSelected ? .white : Color.electricViolet)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.electricViolet : Color.electricViolet.opacity(0.1))
                    )

                Text(profile.rawValue)
                    .font(.obsidianCaption)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .frame(height: 34)

                Text(profile.description)
                    .font(.obsidianSmall)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(3)
                    .frame(height: 45)
            }
            .frame(width: 140)
            .padding(12)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.electricViolet : Color.obsidianBorder.opacity(0.35), lineWidth: isSelected ? 1.5 : 0.5)
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
