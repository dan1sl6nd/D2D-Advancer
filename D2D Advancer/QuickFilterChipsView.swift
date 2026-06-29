import SwiftUI
import UIKit

struct QuickFilterChipsView: View {
    @ObservedObject var searchFilterManager: SearchFilterManager
    @State private var showingSavePreset = false
    @State private var presetName = ""
    @State private var presetSaveErrorMessage: String?

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
                        .font(.themeCaption)
                        .foregroundColor(Color.textSecondary)
                        .glassChip()
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
                        .font(.themeCaption)
                        .foregroundColor(Color.textSecondary)
                        .glassChip()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet(presetName: $presetName) {
                guard searchFilterManager.savePreset(name: presetName) else {
                    presetSaveErrorMessage = searchFilterManager.lastErrorMessage ?? "Preset was not saved."
                    return false
                }
                presetName = ""
                return true
            }
        }
        .alert("Preset not saved", isPresented: Binding(
            get: { presetSaveErrorMessage != nil },
            set: { if !$0 { presetSaveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { presetSaveErrorMessage = nil }
        } message: {
            Text(presetSaveErrorMessage ?? "Preset was not saved.")
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

    @ViewBuilder
    private func chip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(.themeCaption)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.electricViolet)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(.themeCaption)
                .foregroundColor(Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.obsidianSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.obsidianBorder, lineWidth: 1)
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SavePresetSheet: View {
    @Binding var presetName: String
    var onSave: () -> Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedPresetName: String {
        presetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Save Preset",
                        subtitle: "Name this filter setup so you can apply it again fast.",
                        icon: "bookmark.fill"
                    )

                    ObsidianSectionCard(
                        title: "Preset Details",
                        icon: "tray.full.fill",
                        subtitle: "Use a short name that describes the route, status, or follow-up view."
                    ) {
                        LeadFormTextField(
                            title: "Preset Name",
                            placeholder: "Example: Interested today",
                            text: $presetName,
                            icon: "text.cursor"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationTitle("Save Preset")
            .obsidianInlineNavigation()
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: trimmedPresetName.isEmpty,
                    primaryAction: {
                        if onSave() {
                            dismiss()
                        }
                    },
                    secondaryAction: {
                        presetName = ""
                        dismiss()
                    },
                    primaryLabel: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
                .background(Color.obsidianBlack.ignoresSafeArea(edges: .bottom))
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .foregroundColor(Color.electricViolet)
                }
            }
        }
        .presentationBackground(Color.obsidianBlack)
    }
}
