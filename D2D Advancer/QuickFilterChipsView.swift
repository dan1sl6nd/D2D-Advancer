import SwiftUI

struct QuickFilterChipsView: View {
    @ObservedObject var searchFilterManager: SearchFilterManager
    @State private var showingSavePreset = false
    @State private var showingPresetPicker = false
    @State private var presetSaveErrorMessage: String?

    private let quickStatuses: [LeadStatus] = [.new, .interested, .closed, .notInterested]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Status chips
                    ForEach(quickStatuses, id: \.self) { status in
                        chip(
                            title: quickStatusTitle(for: status),
                            icon: status.icon,
                            isSelected: searchFilterManager.currentFilter.selectedStatuses.contains(status),
                            accessibilityLabel: status.displayName
                        ) {
                            toggleStatus(status)
                        }
                        .accessibilityIdentifier("quickFilterStatus_\(status.rawValue)")
                    }

                    // Has Follow-up
                    chip(
                        title: "Follow-up",
                        icon: "calendar.badge.clock",
                        isSelected: searchFilterManager.currentFilter.hasFollowUp == true,
                        accessibilityLabel: "Has Follow-up"
                    ) {
                        toggleHasFollowUp()
                    }
                    .accessibilityIdentifier("quickFilterHasFollowUp")

                    // Due Today (follow-up date today)
                    chip(title: "Due Today", icon: "sun.max", isSelected: isDueTodaySelected) {
                        toggleDueToday()
                    }
                    .accessibilityIdentifier("quickFilterDueToday")

                    // Clear
                    Button(action: { searchFilterManager.clearAllFilters() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text("Clear")
                        }
                        .font(.themeCaption)
                        .foregroundColor(Color.textSecondary)
                        .frame(minHeight: 44)
                        .glassChip()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("quickFilterClearButton")

                    Button {
                        showingPresetPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.full")
                            Text("Presets")
                        }
                        .font(.themeCaption)
                        .foregroundColor(Color.textSecondary)
                        .frame(minHeight: 44)
                        .glassChip()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("quickFilterPresetsMenu")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("quickFilterChipScroller")
        }
        .sheet(isPresented: $showingPresetPicker) {
            QuickFilterPresetPickerSheet(
                presets: searchFilterManager.savedPresets,
                onSaveCurrent: {
                    showingPresetPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showingSavePreset = true
                    }
                },
                onLoadPreset: { preset in
                    searchFilterManager.loadPreset(preset)
                    showingPresetPicker = false
                },
                onDeletePreset: { preset in
                    if !searchFilterManager.deletePreset(preset) {
                        presetSaveErrorMessage = searchFilterManager.lastErrorMessage ?? "Preset was not deleted."
                    }
                }
            )
        }
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet { presetName in
                guard searchFilterManager.savePreset(name: presetName) else {
                    presetSaveErrorMessage = searchFilterManager.lastErrorMessage ?? "Preset was not saved."
                    return false
                }
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

    private func quickStatusTitle(for status: LeadStatus) -> String {
        switch status {
        case .closed:
            return "Sold"
        case .notInterested:
            return "Pass"
        default:
            return status.displayName
        }
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
    private func chip(
        title: String,
        icon: String,
        isSelected: Bool,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .font(.themeCaption)
            .foregroundColor(isSelected ? .white : Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(isSelected ? Color.electricViolet : Color.obsidianSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.obsidianBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct QuickFilterPresetPickerSheet: View {
    let presets: [SearchPreset]
    let onSaveCurrent: () -> Void
    let onLoadPreset: (SearchPreset) -> Void
    let onDeletePreset: (SearchPreset) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Filter Presets",
                        subtitle: "Save this view or load a saved filter setup.",
                        icon: "tray.full.fill"
                    )

                    ObsidianSectionCard(
                        title: "Current Filter",
                        icon: "bookmark.fill",
                        subtitle: "Store the selected statuses, dates, and follow-up filters."
                    ) {
                        Button(action: onSaveCurrent) {
                            Label("Save Current", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ObsidianPrimaryButtonStyle())
                        .accessibilityIdentifier("quickFilterSaveCurrentButton")
                    }

                    ObsidianSectionCard(
                        title: "Saved Presets",
                        icon: "folder.fill",
                        subtitle: presets.isEmpty ? "No saved presets yet." : "\(presets.count) saved \(presets.count == 1 ? "preset" : "presets")"
                    ) {
                        if presets.isEmpty {
                            ObsidianEmptyState(
                                icon: "tray",
                                title: "No presets",
                                message: "Save the current filter when you want to reuse it."
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(presets) { preset in
                                    QuickFilterPresetRow(
                                        preset: preset,
                                        onLoad: {
                                            onLoadPreset(preset)
                                        },
                                        onDelete: {
                                            onDeletePreset(preset)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(screenBackground.ignoresSafeArea())
            .obsidianPushedNavigation(
                "Filter Presets",
                backButtonAccessibilityIdentifier: "quickFilterPresetPickerBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                Button(action: { dismiss() }) {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .accessibilityIdentifier("quickFilterPresetPickerCloseButton")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(screenBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .presentationBackground(screenBackground)
        .accessibilityIdentifier("quickFilterPresetPickerSheet")
    }
}

private struct QuickFilterPresetRow: View {
    let preset: SearchPreset
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onLoad) {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 34, height: 34)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.name)
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Text(preset.dateCreated, style: .date)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("quickFilterPreset_\(preset.id.uuidString)")
            .accessibilityLabel(preset.name)

            ObsidianCompactIconButton(
                icon: "trash",
                accessibilityLabel: "Delete \(preset.name)",
                accentColor: Color.statusNotInterested,
                backgroundColor: Color.statusNotInterested.opacity(0.12),
                foregroundColor: Color.statusNotInterested,
                borderColor: Color.statusNotInterested.opacity(0.2),
                size: 44,
                action: onDelete
            )
            .accessibilityIdentifier("quickFilterDeletePreset_\(preset.id.uuidString)")
        }
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
    }
}

struct SavePresetSheet: View {
    var onSave: (String) -> Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var presetName = ""

    private var trimmedPresetName: String {
        presetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let screenBackground = Color.obsidianBackground(for: colorScheme)

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
                            icon: "text.cursor",
                            accessibilityIdentifier: "quickFilterPresetNameField"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(screenBackground.ignoresSafeArea())
            .obsidianPushedNavigation(
                "Save Preset",
                backButtonAccessibilityIdentifier: "quickFilterSavePresetBackButton",
                onBack: { dismiss() }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: trimmedPresetName.isEmpty,
                    primaryAction: {
                        let name = trimmedPresetName
                        if onSave(name) {
                            dismiss()
                        }
                    },
                    secondaryAction: {
                        dismiss()
                    },
                    primaryLabel: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
                .accessibilityIdentifier("quickFilterSavePresetActionBar")
                .background(screenBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .presentationBackground(screenBackground)
        .accessibilityIdentifier("quickFilterSavePresetSheet")
    }
}
