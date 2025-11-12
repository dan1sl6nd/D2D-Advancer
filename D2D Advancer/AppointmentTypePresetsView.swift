import SwiftUI

struct AppointmentTypePresetsView: View {
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingCreateView = false
    @State private var editingType: CustomAppointmentType?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Default Types Card
                        defaultTypesCard
                        
                        // Custom Types Card
                        customTypesCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Appointment Types")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button(action: {
                        showingCreateView = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground).opacity(0.95))
            }
            .safeAreaInset(edge: .bottom) {
                // Card-based Done button
                Button(action: {
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                        Text("Done")
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
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(isPresented: $showingCreateView) {
                CustomAppointmentTypeCreatorView()
            }
            .sheet(item: $editingType) { type in
                CustomAppointmentTypeCreatorView(editingType: type)
            }
        }
    }
    
    private var defaultTypesCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Default Types")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("These are the built-in appointment types that cannot be modified.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 12)
                ], spacing: 12) {
                    ForEach(Appointment.AppointmentType.allCases, id: \.self) { type in
                        DefaultTypeChip(type: type)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var customTypesCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "paintbrush.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Custom Types")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Add New") { showingCreateView = true }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            if customTypeManager.customTypes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Custom Types")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Create custom appointment types that fit your specific business needs.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    
                    Button("Create First Type") { showingCreateView = true }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap to edit or swipe to delete custom appointment types.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 140), spacing: 12)
                    ], spacing: 12) {
                        ForEach(customTypeManager.customTypes) { customType in
                            CustomTypeChip(
                                customType: customType,
                                onEdit: {
                                    editingType = customType
                                },
                                onDelete: {
                                    withAnimation {
                                        customTypeManager.deleteCustomType(customType)
                                    }
                                }
                            )
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

    // No gating; all users can create unlimited custom types
}

struct DefaultTypeChip: View {
    let type: Appointment.AppointmentType
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundColor(type.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Built-in")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(type.color.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct CustomTypeChip: View {
    let customType: CustomAppointmentType
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: customType.icon)
                .font(.title3)
                .foregroundColor(customType.swiftUIColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(customType.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Custom")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(customType.swiftUIColor.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(customType.swiftUIColor.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            onEdit()
        }
        .alert("Delete Appointment Type", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete '\(customType.name)'? This action cannot be undone.")
        }
    }
}

#Preview {
    AppointmentTypePresetsView()
}
