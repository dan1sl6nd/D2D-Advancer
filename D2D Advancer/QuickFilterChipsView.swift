import SwiftUI
import UIKit

struct QuickFilterChipsView: View {
    @ObservedObject var searchFilterManager: SearchFilterManager
    @State private var showingSavePreset = false
    @State private var presetName = ""

    private let quickStatuses: [LeadStatus] = [.new, .interested, .closed, .notInterested]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Status chips
                    ForEach(quickStatuses, id: \.self) { status in
                        chip(title: status.displayName, icon: status.icon, isSelected: searchFilterManager.currentFilter.selectedStatuses.contains(status)) {
                            toggleStatus(status)
                        }
                    }

                    // Has Follow-up
                    chip(title: "Has Follow-up", icon: "calendar.badge.clock", isSelected: searchFilterManager.currentFilter.hasFollowUp == true) {
                        toggleHasFollowUp()
                    }

                    // Due Today (follow-up date today)
                    chip(title: "Due Today", icon: "sun.max", isSelected: isDueTodaySelected) {
                        toggleDueToday()
                    }

                    // Clear
                    Button(action: { searchFilterManager.clearAllFilters() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text("Clear")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
                    }

                    // Presets menu
                    Menu {
                        Button("Save Current…") { showingSavePreset = true }
                        if !searchFilterManager.savedPresets.isEmpty {
                            Divider()
                            ForEach(searchFilterManager.savedPresets) { preset in
                                Button(preset.name) { searchFilterManager.loadPreset(preset) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full")
                            Text("Presets")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet(presetName: $presetName) {
                if !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchFilterManager.savePreset(name: presetName)
                }
                presetName = ""
            }
        }
    }

    private var isDueTodaySelected: Bool {
        if let range = searchFilterManager.currentFilter.dateRange, range.type == .followUp {
            let cal = Calendar.current
            return cal.isDateInToday(range.startDate) && cal.isDateInToday(range.endDate)
        }
        return false
    }

    private func toggleStatus(_ status: LeadStatus) {
        var set = searchFilterManager.currentFilter.selectedStatuses
        if set.contains(status) {
            set.remove(status)
        } else {
            set.insert(status)
        }
        searchFilterManager.currentFilter.selectedStatuses = set
    }

    private func toggleHasFollowUp() {
        if searchFilterManager.currentFilter.hasFollowUp == true {
            searchFilterManager.currentFilter.hasFollowUp = nil
        } else {
            searchFilterManager.currentFilter.hasFollowUp = true
        }
    }

    private func toggleDueToday() {
        let cal = Calendar.current
        if isDueTodaySelected {
            searchFilterManager.currentFilter.dateRange = nil
        } else {
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
            searchFilterManager.currentFilter.dateRange = DateRange(startDate: start, endDate: end, type: .followUp)
        }
    }

    private func chip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.themePrimary.opacity(0.15) : Color(UIColor.tertiarySystemBackground))
            .foregroundColor(isSelected ? Color.themePrimary : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.themePrimary : Color(UIColor.separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SavePresetSheet: View {
    @Binding var presetName: String
    var onSave: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                Spacer()
            }
            .navigationTitle("Save Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presetName = ""; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
