import SwiftUI

struct SeasonalDatePickerView: View {
    @Binding var selectedDate: Date?
    let onCompletion: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedPreset: SeasonalDatePreset?
    @State private var customDate: Date = Date()
    @State private var useCustomDate = false
    
    private let presetManager = SeasonalDatePresetManager.shared
    private let presets: [SeasonalDatePreset]
    
    init(selectedDate: Binding<Date?>, onCompletion: (() -> Void)? = nil) {
        self._selectedDate = selectedDate
        self.onCompletion = onCompletion
        self.presets = SeasonalDatePresetManager.shared.generatePresets()
        
        // Initialize custom date with current selection or default
        if let currentDate = selectedDate.wrappedValue {
            _customDate = State(initialValue: currentDate)
        } else {
            _customDate = State(initialValue: Date())
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Follow Up Date",
                        subtitle: "Pick a seasonal preset or set an exact follow-up time.",
                        icon: "calendar.badge.clock"
                    )

                    headerSection
                    seasonalPresetsSection
                    customDateSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("seasonalDatePickerScreen")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Follow Up Date",
                backButtonAccessibilityIdentifier: "seasonalDatePickerBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !hasSelection,
                    primaryAccessibilityIdentifier: "seasonalDatePickerSetButton",
                    secondaryAccessibilityIdentifier: "seasonalDatePickerCancelButton",
                    primaryAction: saveDate,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label("Set Date", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
        }
        .presentationBackground(Color.obsidianBackground(for: colorScheme))
    }
    
    private var hasSelection: Bool {
        selectedPreset != nil || useCustomDate
    }
    
    private var headerSection: some View {
        LeadFormSectionCard(title: "Choose Follow-Up Time", icon: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a seasonal period for your follow-up, and we'll automatically choose a date that matches today's date.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)

                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color.electricViolet)
                        .font(.caption)

                    Text("Dates are calculated to match \(formattedCurrentDay())")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.electricViolet)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.electricViolet.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    private var seasonalPresetsSection: some View {
        LeadFormSectionCard(title: "Seasonal Presets", icon: "leaf.fill") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                ForEach(Array(presets.prefix(8).enumerated()), id: \.element.id) { index, preset in
                    SeasonalPresetCard(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id
                    ) {
                        selectedPreset = preset
                        useCustomDate = false
                    }
                    .accessibilityIdentifier("seasonalPreset_\(index)")
                }
            }
            .clipped()
        }
    }

    private var customDateSection: some View {
        LeadFormSectionCard(title: "Custom Date", icon: "calendar") {
            HStack {
                Text("Use exact date")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)

                Spacer()

                Toggle("Use custom follow-up date", isOn: $useCustomDate)
                    .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                    .labelsHidden()
                    .accessibilityLabel("Use custom follow-up date")
                    .accessibilityIdentifier("seasonalDatePickerCustomToggle")
                    .accessibilityValue(useCustomDate ? "Enabled" : "Disabled")
                    .accessibilityHint("Shows an exact date and time picker.")
                    .onChange(of: useCustomDate) { _, newValue in
                        if newValue {
                            selectedPreset = nil
                        }
                    }
            }
            
            if useCustomDate {
                DatePicker("Select Date & Time", selection: $customDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("seasonalDatePickerCustomDatePicker")
            }
        }
    }

    private func saveDate() {
        if let preset = selectedPreset {
            selectedDate = preset.calculatedDate
        } else if useCustomDate {
            selectedDate = customDate
        }
        onCompletion?()
        dismiss()
    }
    
    private func formattedCurrentDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date())
    }
}

struct SeasonalPresetCard: View {
    let preset: SeasonalDatePreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Season Icon
                Image(systemName: preset.season.icon)
                    .font(.obsidianCallout)
                    .foregroundColor(isSelected ? .white : colorForSeason(preset.season))
                
                // Season Title
                VStack(spacing: 2) {
                    Text(preset.season.rawValue)
                        .font(.obsidianFootnote)
                        .foregroundColor(isSelected ? .white : Color.textPrimary)
                        .lineLimit(1)

                    Text(verbatim: "\(preset.year)")
                        .font(.obsidianSmall)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Color.textSecondary)
                }
                
                // Calculated Date
                VStack(spacing: 1) {
                    Text(formattedDate(preset.calculatedDate))
                        .font(.micro)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : Color.textSecondary)
                        .lineLimit(1)

                    Text(formattedTime(preset.calculatedDate))
                        .font(.micro)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100, maxHeight: 120)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected ?
                        colorForSeason(preset.season) :
                        Color.obsidianSurface
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ?
                        colorForSeason(preset.season) :
                        Color.obsidianBorder.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func colorForSeason(_ season: SeasonalDatePreset.Season) -> Color {
        switch season.color {
        case "green": return .green
        case "orange": return .orange
        case "brown": return .brown
        case "blue": return .blue
        default: return .blue
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    SeasonalDatePickerView(selectedDate: .constant(nil))
}
