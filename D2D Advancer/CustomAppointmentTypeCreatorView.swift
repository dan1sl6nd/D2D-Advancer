import SwiftUI

struct CustomAppointmentTypeCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var typeManager = CustomAppointmentTypeManager.shared
    
    @State private var typeName: String = ""
    @State private var selectedIcon: String = "calendar"
    @State private var selectedColor: String = "blue"
    @State private var showingIconPicker = false
    @State private var showingPreview = false
    
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
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Type Details Card
                        typeDetailsCard
                        
                        // Appearance Card
                        appearanceCard
                        
                        // Preview Card
                        previewCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle(editingType != nil ? "Edit Type" : "Create Type")
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
                        saveType()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text(editingType != nil ? "Update Type" : "Create Type")
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
                                            !isValidType ? Color.gray : Color.blue,
                                            !isValidType ? Color.gray.opacity(0.8) : Color.blue.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: !isValidType ? .clear : .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(!isValidType)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
        }
    }
    
    private var typeDetailsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Type Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Type Name Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Type Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter type name", text: $typeName)
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
    
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "paintbrush.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Appearance")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Icon Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Icon")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Button(action: {
                    showingIconPicker = true
                }) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(selectedColorObj)
                            .font(.title3)
                            .frame(width: 24)
                        
                        Text("Tap to change icon")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Color Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
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
            
            // Preview Display
            VStack(alignment: .leading, spacing: 16) {
                Text("How your appointment type will appear:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Preview Chip
                HStack {
                    Image(systemName: selectedIcon)
                        .foregroundColor(selectedColorObj)
                        .font(.title3)
                        .frame(width: 24)
                    
                    Text(typeName.isEmpty ? "New Appointment Type" : typeName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
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
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
        
        if editingType != nil {
            typeManager.updateCustomType(customType)
        } else {
            typeManager.addCustomType(customType)
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
                    .foregroundColor(isSelected ? color : .secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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
        NavigationView {
            VStack {
                IconSearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(iconsByCategory.keys.sorted(), id: \.self) { category in
                            VStack(alignment: .leading, spacing: 12) {
                                // Category Header
                                HStack {
                                    Text(category)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    
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
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .frame(width: 28, height: 28)
                
                Text(iconData.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(minWidth: 85, minHeight: 75)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(UIColor.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IconSearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search icons...", text: $text)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

#Preview {
    CustomAppointmentTypeCreatorView()
}