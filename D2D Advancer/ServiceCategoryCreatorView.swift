import SwiftUI

struct ServiceCategoryCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var categoryManager = ServiceCategoryManager.shared
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "drop.fill"
    @State private var selectedColor: String = "blue"
    
    let editingCategory: ServiceCategory?
    
    init(editingCategory: ServiceCategory? = nil) {
        self.editingCategory = editingCategory
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
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Category Info Card
                        categoryDetailsCard
                        
                        // Icon Selection Card
                        iconSelectionCard
                        
                        // Color Selection Card
                        colorSelectionCard
                        
                        // Preview Card
                        previewCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle(editingCategory != nil ? "Edit Service" : "Add Service")
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
                        saveCategory()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text(editingCategory != nil ? "Update" : "Add Service")
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
                                            !isValidCategory ? Color.gray : colorForName(selectedColor),
                                            !isValidCategory ? Color.gray.opacity(0.8) : colorForName(selectedColor).opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: !isValidCategory ? .clear : colorForName(selectedColor).opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(!isValidCategory)
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
    
    private var categoryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Service Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Service Name Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Service Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter service name", text: $name)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var iconSelectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "app.badge.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Choose Icon")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Icon Grid
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
                                    .fill(selectedIcon == icon ? colorForName(selectedColor) : Color(UIColor.tertiarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedIcon == icon ? colorForName(selectedColor) : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var colorSelectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Choose Color")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Color Grid
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
                                    .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
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
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Preview")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Preview
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
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Custom Service Category")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
        
        if editingCategory != nil {
            categoryManager.updateCustomCategory(category)
        } else {
            categoryManager.addCustomCategory(category)
        }
        
        dismiss()
    }
}

#Preview {
    ServiceCategoryCreatorView()
}