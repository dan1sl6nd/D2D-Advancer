import SwiftUI

struct CustomAppointmentTypeCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var typeManager = CustomAppointmentTypeManager.shared
    
    @State private var typeName: String = ""
    @State private var selectedIcon: String = "calendar"
    @State private var selectedColor: String = "blue"
    @State private var showingIconPicker = false
    @State private var showingPreview = false
    @State private var saveErrorMessage: String?
    
    let editingType: CustomAppointmentType?
    
    init(editingType: CustomAppointmentType? = nil) {
        self.editingType = editingType
        if let type = editingType {
            _typeName = State(initialValue: type.name)
            _selectedIcon = State(initialValue: type.icon)
            _selectedColor = State(initialValue: type.color)
        }
    }
    
    private var isValidType: Bool {
        !typeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var selectedColorObj: Color {
        switch selectedColor.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        case "brown": return .brown
        case "cyan": return .cyan
        case "mint": return .mint
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: editingType != nil ? "Edit Type" : "Create Type",
                        subtitle: "Customize appointment labels used in scheduling.",
                        icon: "calendar.badge.plus"
                    )
                    .accessibilityIdentifier("customAppointmentTypeEditor")

                    typeDetailsCard
                    appearanceCard
                    previewCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 112)
            }
            .obsidianScreenBackground()
            .navigationTitle(editingType != nil ? "Edit Type" : "Create Type")
            .obsidianInlineNavigation()
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !isValidType,
                    primaryAccessibilityIdentifier: "customAppointmentTypeSaveButton",
                    secondaryAccessibilityIdentifier: "customAppointmentTypeCancelButton",
                    primaryAction: saveType,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label(editingType != nil ? "Update" : "Create", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .alert(
                "Type not saved",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
        }
    }
    
    private var typeDetailsCard: some View {
        ObsidianSectionCard(
            title: "Type Details",
            icon: "tag.fill",
            subtitle: "The name shown in appointment lists and details."
        ) {
            LeadFormTextField(
                title: "Type Name",
                placeholder: "Enter type name",
                text: $typeName,
                icon: "tag.fill",
                accessibilityIdentifier: "customAppointmentTypeNameField"
            )
        }
    }

    private var appearanceCard: some View {
        ObsidianSectionCard(
            title: "Appearance",
            icon: "paintbrush.fill",
            subtitle: "Pick an icon and color that are easy to scan."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Icon")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                
                Button(action: {
                    showingIconPicker = true
                }) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(selectedColorObj)
                            .font(.obsidianCallout)
                            .frame(width: 24)
                        
                        Text("Tap to change icon")
                            .foregroundColor(Color.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(Color.textSecondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianSurface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("customAppointmentTypeIconButton")
            }
            
            // Color Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 60), spacing: 12)
                ], spacing: 12) {
                    ForEach(CustomAppointmentTypeManager.availableColors, id: \.1) { colorName, colorValue in
                        ColorSelectionChip(
                            colorName: colorName,
                            colorValue: colorValue,
                            isSelected: selectedColor == colorValue
                        ) {
                            selectedColor = colorValue
                        }
                    }
                }
            }
        }
    }

    private var previewCard: some View {
        ObsidianSectionCard(
            title: "Preview",
            icon: "eye.fill",
            subtitle: "How this type appears in scheduling."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("How your appointment type will appear:")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
                // Preview Chip
                HStack {
                    Image(systemName: selectedIcon)
                        .foregroundColor(selectedColorObj)
                        .font(.obsidianCallout)
                        .frame(width: 24)
                    
                    Text(typeName.isEmpty ? "New Appointment Type" : typeName)
                        .font(.obsidianBody)
                        .foregroundColor(Color.textPrimary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(selectedColorObj.opacity(0.15))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selectedColorObj.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private func saveType() {
        let customType = CustomAppointmentType(
            id: editingType?.id ?? UUID().uuidString,
            name: typeName.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: selectedIcon,
            color: selectedColor,
            isDefault: false,
            dateCreated: editingType?.dateCreated ?? Date()
        )
        
        let didSave: Bool
        if editingType != nil {
            didSave = typeManager.updateCustomType(customType)
        } else {
            didSave = typeManager.addCustomType(customType)
        }

        guard didSave else {
            saveErrorMessage = typeManager.lastErrorMessage ?? "Could not save this appointment type. Please try again."
            return
        }
        
        dismiss()
    }
}

struct ColorSelectionChip: View {
    let colorName: String
    let colorValue: String
    let isSelected: Bool
    let action: () -> Void
    
    private var color: Color {
        switch colorValue.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        case "brown": return .brown
        case "cyan": return .cyan
        case "mint": return .mint
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .opacity(isSelected ? 1 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(color, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                    )
                
                Text(colorName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? color : Color.textSecondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("customAppointmentTypeColor_\(colorValue)")
    }
}

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    @State private var searchText = ""
    
    private var filteredIcons: [(symbol: String, name: String, category: String)] {
        if searchText.isEmpty {
            return CustomAppointmentTypeManager.availableIcons
        } else {
            return CustomAppointmentTypeManager.availableIcons.filter { icon in
                icon.name.localizedCaseInsensitiveContains(searchText) ||
                icon.category.localizedCaseInsensitiveContains(searchText) ||
                icon.symbol.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var iconsByCategory: [String: [(symbol: String, name: String, category: String)]] {
        Dictionary(grouping: filteredIcons) { $0.category }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                IconSearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(iconsByCategory.keys.sorted(), id: \.self) { category in
                            VStack(alignment: .leading, spacing: 12) {
                                // Category Header
                                HStack {
                                    Text(category)
                                        .font(.obsidianTitle)
                                        .foregroundColor(Color.textPrimary)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                
                                // Icons Grid for this category
                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 90), spacing: 12)
                                ], spacing: 12) {
                                    ForEach(iconsByCategory[category] ?? [], id: \.symbol) { iconData in
                                        IconSelectionChip(
                                            iconData: iconData,
                                            isSelected: selectedIcon == iconData.symbol
                                        ) {
                                            selectedIcon = iconData.symbol
                                            dismiss()
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .obsidianScreenBackground()
            .navigationTitle("Choose Icon")
            .obsidianInlineNavigation()
            .accessibilityIdentifier("customAppointmentTypeIconPicker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ObsidianCompactIconButton(
                        icon: "checkmark",
                        accessibilityLabel: "Done choosing icon",
                        accentColor: Color.electricViolet,
                        accessibilityIdentifier: "customAppointmentTypeIconPickerDoneButton"
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct IconSelectionChip: View {
    let iconData: (symbol: String, name: String, category: String)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: iconData.symbol)
                    .font(.obsidianCallout)
                    .foregroundColor(isSelected ? Color.electricViolet : Color.textPrimary)
                    .frame(width: 28, height: 28)

                Text(iconData.name)
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(minWidth: 85, minHeight: 75)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.electricViolet.opacity(0.15) : Color.obsidianSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.electricViolet : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("customAppointmentTypeIcon_\(iconData.symbol)")
    }
}

struct IconSearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.textSecondary)

            TextField("Search icons...", text: $text)
                .font(.obsidianBody)
                .foregroundColor(Color.textPrimary)
                .accessibilityIdentifier("customAppointmentTypeIconSearchField")

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.obsidianSurface)
        .cornerRadius(10)
        .accessibilityIdentifier("customAppointmentTypeIconSearchBar")
    }
}

#Preview {
    CustomAppointmentTypeCreatorView()
}
