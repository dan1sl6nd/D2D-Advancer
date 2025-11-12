import SwiftUI

struct SeasonalDatePickerView: View {
    @Binding var selectedDate: Date?
    let onCompletion: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    
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
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        // Header explanation
                        headerSection
                        
                        // Seasonal Presets
                        seasonalPresetsSection
                        
                        // Custom Date Option
                        customDateSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Follow Up Date")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                HStack(spacing: 16) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                            Text("Cancel")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }
                    
                    Button(action: {
                        saveDate()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Set Date")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            hasSelection ? Color.blue : Color.gray,
                                            hasSelection ? Color.blue.opacity(0.8) : Color.gray.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: hasSelection ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(!hasSelection)
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
    
    private var hasSelection: Bool {
        selectedPreset != nil || useCustomDate
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Choose Follow-Up Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a seasonal period for your follow-up, and we'll automatically choose a date that matches today's date.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("Dates are calculated to match \(formattedCurrentDay())")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var seasonalPresetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("Seasonal Presets")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                ForEach(presets.prefix(8), id: \.id) { preset in
                    SeasonalPresetCard(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id
                    ) {
                        selectedPreset = preset
                        useCustomDate = false
                    }
                }
            }
            .clipped()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var customDateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.purple)
                    .font(.title2)
                
                Text("Custom Date")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Toggle("", isOn: $useCustomDate)
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
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
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : colorForSeason(preset.season))
                
                // Season Title
                VStack(spacing: 2) {
                    Text(preset.season.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    
                    Text("\(preset.year)")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                // Calculated Date
                VStack(spacing: 1) {
                    Text(formattedDate(preset.calculatedDate))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(1)
                    
                    Text(formattedTime(preset.calculatedDate))
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100, maxHeight: 120)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ? 
                        colorForSeason(preset.season) : 
                        Color(UIColor.tertiarySystemBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? 
                        colorForSeason(preset.season) : 
                        Color(UIColor.separator).opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
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