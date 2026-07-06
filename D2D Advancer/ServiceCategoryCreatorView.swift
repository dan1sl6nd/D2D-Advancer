import SwiftUI

struct ServiceCategoryCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "drop.fill"
    @State private var selectedColor: String = "blue"
    @State private var saveErrorMessage: String?
    
    let editingCategory: ServiceCategory?
    let onSave: ((ServiceCategory) -> Void)?
    
    init(editingCategory: ServiceCategory? = nil, onSave: ((ServiceCategory) -> Void)? = nil) {
        self.editingCategory = editingCategory
        self.onSave = onSave
        if let category = editingCategory {
            _name = State(initialValue: category.name)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColor = State(initialValue: category.color)
        }
    }
    
    private var isValidCategory: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: editingCategory != nil ? "Edit Service" : "Add Service",
                        subtitle: "Name, icon, and color used across lead forms.",
                        icon: "tag.fill"
                    )
                    .accessibilityIdentifier("serviceCategoryEditor")

                    categoryDetailsCard
                    iconSelectionCard
                    colorSelectionCard
                    previewCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .obsidianScreenBackground()
            .navigationTitle(editingCategory != nil ? "Edit Service" : "Add Service")
            .obsidianInlineNavigation()
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ObsidianBackButton(accessibilityIdentifier: "serviceCategoryBackButton") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !isValidCategory,
                    primaryAccessibilityIdentifier: "serviceCategorySaveButton",
                    secondaryAccessibilityIdentifier: "serviceCategoryCancelButton",
                    primaryAction: saveCategory,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label(editingCategory != nil ? "Update" : "Add", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
            .alert(
                "Service not saved",
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
    
    private var categoryDetailsCard: some View {
        ObsidianSectionCard(
            title: "Service Details",
            icon: "tag.fill",
            subtitle: "This is what you will pick when creating or editing leads."
        ) {
            LeadFormTextField(
                title: "Service Name",
                placeholder: "Enter service name",
                text: $name,
                icon: "tag.fill",
                accessibilityIdentifier: "serviceCategoryNameField"
            )
        }
    }
    
    private var iconSelectionCard: some View {
        ObsidianSectionCard(
            title: "Choose Icon",
            icon: "app.badge.fill",
            subtitle: "Use a recognizable symbol for this service."
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(ServiceCategory.availableIcons, id: \.self) { icon in
                    Button(action: {
                        selectedIcon = icon
                    }) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(selectedIcon == icon ? .white : colorForName(selectedColor))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIcon == icon ? colorForName(selectedColor) : Color.obsidianElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedIcon == icon ? colorForName(selectedColor) : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("serviceCategoryIcon_\(icon)")
                }
            }
        }
    }
    
    private var colorSelectionCard: some View {
        ObsidianSectionCard(
            title: "Choose Color",
            icon: "paintpalette.fill",
            subtitle: "Color helps this service stand out in lists."
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(ServiceCategory.availableColors, id: \.self) { color in
                    Button(action: {
                        selectedColor = color
                    }) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorForName(color))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedColor == color ? Color.textPrimary : Color.clear, lineWidth: 3)
                            )
                            .overlay(
                                selectedColor == color ?
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                : nil
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("serviceCategoryColor_\(color)")
                }
            }
        }
    }
    
    private var previewCard: some View {
        ObsidianSectionCard(
            title: "Preview",
            icon: "eye.fill",
            subtitle: "How this service will appear in the app."
        ) {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundColor(colorForName(selectedColor))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorForName(selectedColor).opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? "Service Name" : name)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)
                    
                    Text("Custom Service Category")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    private func colorForName(_ colorName: String) -> Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "indigo": return .indigo
        case "teal": return .teal
        case "mint": return .mint
        case "cyan": return .cyan
        case "brown": return .brown
        default: return .blue
        }
    }
    
    private func saveCategory() {
        let category = ServiceCategory(
            id: editingCategory?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: selectedIcon,
            color: selectedColor,
            isCustom: true,
            dateCreated: editingCategory?.dateCreated ?? Date()
        )
        
        let didSave: Bool
        if editingCategory != nil {
            didSave = categoryManager.updateCustomCategory(category)
        } else {
            didSave = categoryManager.addCustomCategory(category)
        }

        guard didSave else {
            saveErrorMessage = categoryManager.lastErrorMessage ?? "Could not save this service. Please try again."
            return
        }

        onSave?(category)
        dismiss()
    }
}

#Preview {
    ServiceCategoryCreatorView()
}
