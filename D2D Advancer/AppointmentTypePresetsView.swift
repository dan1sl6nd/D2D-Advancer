import SwiftUI

struct AppointmentTypePresetsView: View {
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingCreateView = false
    @State private var editingType: CustomAppointmentType?
    @State private var deleteErrorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Appointment Types",
                        subtitle: "Manage default and custom job labels.",
                        icon: "calendar.badge.plus"
                    )
                    .accessibilityIdentifier("appointmentTypesScreen")

                    defaultTypesCard
                    customTypesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 112)
            }
            .obsidianScreenBackground()
            .navigationTitle("Appointment Types")
            .obsidianInlineNavigation()
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ObsidianCompactIconButton(
                        icon: "plus",
                        accessibilityLabel: "Create appointment type",
                        accessibilityIdentifier: "appointmentTypesCreateButton",
                        action: { showingCreateView = true }
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: { dismiss() }) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianPrimaryButtonStyle())
                .accessibilityIdentifier("appointmentTypesDoneButton")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.obsidianBackground(for: colorScheme))
            }
            .sheet(isPresented: $showingCreateView) {
                CustomAppointmentTypeCreatorView()
            }
            .sheet(item: $editingType) { type in
                CustomAppointmentTypeCreatorView(editingType: type)
            }
            .alert(
                "Type not deleted",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "Please try again.")
            }
        }
    }
    
    private var defaultTypesCard: some View {
        ObsidianSectionCard(
            title: "Default Types",
            icon: "star.fill",
            subtitle: "Built-in appointment types that cannot be modified."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 10)
                ], spacing: 10) {
                    ForEach(Appointment.AppointmentType.allCases, id: \.self) { type in
                        DefaultTypeChip(type: type)
                    }
                }
            }
        }
    }

    private var customTypesCard: some View {
        ObsidianSectionCard(
            title: "Custom Types",
            icon: "paintbrush.fill",
            subtitle: "Create appointment types that fit your business."
        ) {
            if customTypeManager.customTypes.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    ObsidianIconTile(icon: "calendar.badge.plus", tint: Color.electricViolet, size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("No Custom Types")
                            .font(.obsidianCallout)
                            .foregroundColor(.textPrimary)

                        Text("Add a job label for work your crew repeats often.")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button(action: { showingCreateView = true }) {
                        Image(systemName: "plus")
                            .font(.obsidianCallout)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(ObsidianSecondaryButtonStyle())
                    .controlSize(.small)
                    .accessibilityLabel("Create first appointment type")
                    .accessibilityIdentifier("appointmentTypesCreateFirstButton")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap to edit or swipe to delete custom appointment types.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150), spacing: 10)
                    ], spacing: 10) {
                        ForEach(customTypeManager.customTypes) { customType in
                            CustomTypeChip(
                                customType: customType,
                                onEdit: {
                                    editingType = customType
                                },
                                onDelete: {
                                    withAnimation {
                                        let didDelete = customTypeManager.deleteCustomType(customType)
                                        if !didDelete {
                                            deleteErrorMessage = customTypeManager.lastErrorMessage ?? "Could not delete this appointment type. Please try again."
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
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
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Built-in")
                    .font(.nano)
                    .foregroundColor(Color.textSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(type.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Custom")
                    .font(.nano)
                    .foregroundColor(Color.textSecondary)
            }
            
            Spacer()
            
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(Color.textSecondary)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(customType.swiftUIColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(customType.swiftUIColor.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            onEdit()
        }
        .accessibilityIdentifier("customAppointmentTypeRow")
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
