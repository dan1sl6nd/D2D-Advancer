import SwiftUI

struct AppointmentTypePresetsView: View {
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingCreateView = false
    @State private var editingType: CustomAppointmentType?
    @State private var deleteErrorMessage: String?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ObsidianScreenTitle(
                    title: "Appointment Types",
                    subtitle: "Manage the job labels used when scheduling work.",
                    icon: "calendar.badge.plus"
                )
                .accessibilityIdentifier("appointmentTypesScreen")

                defaultTypesCard
                customTypesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .obsidianScreenBackground()
        .obsidianPushedNavigation("Appointment Types", backButtonAccessibilityIdentifier: "appointmentTypesBackButton")
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
    
    private var defaultTypesCard: some View {
        ObsidianSectionCard(
            title: "Default Types",
            icon: "star.fill",
            subtitle: "Built-in labels available to every appointment."
        ) {
            VStack(spacing: 10) {
                ForEach(Appointment.AppointmentType.allCases, id: \.self) { type in
                    DefaultTypeChip(type: type)
                }
            }
        }
    }

    private var customTypesCard: some View {
        ObsidianSectionCard(
            title: "Custom Types",
            icon: "paintbrush.fill",
            subtitle: "Add the service names your crew actually uses."
        ) {
            VStack(spacing: 12) {
                createTypeButton

                if customTypeManager.customTypes.isEmpty {
                    ObsidianStatusBanner(
                        icon: "calendar.badge.plus",
                        title: "No Custom Types",
                        message: "Add a reusable label for work your crew repeats often.",
                        tint: Color.electricViolet
                    )
                } else {
                    Text("Tap to edit or swipe to delete custom appointment types.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)

                    VStack(spacing: 10) {
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

    private var createTypeButton: some View {
        Button {
            showingCreateView = true
        } label: {
            HStack(spacing: 12) {
                ObsidianIconTile(icon: "plus", tint: Color.electricViolet, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Custom Type")
                        .font(.obsidianCallout)
                        .foregroundColor(Color.textPrimary)

                    Text("Create a reusable appointment label.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.obsidianFootnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.electricViolet)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.electricViolet.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.electricViolet.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("appointmentTypesCreateButton")
    }

    // No gating; all users can create unlimited custom types
}

struct DefaultTypeChip: View {
    let type: Appointment.AppointmentType
    
    var body: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: type.icon, tint: type.color, size: 38)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Built-in")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(type.color.opacity(0.24), lineWidth: 0.5)
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
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    ObsidianIconTile(icon: customType.icon, tint: customType.swiftUIColor, size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(customType.name)
                            .font(.obsidianCallout)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Custom")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(Color.textSecondary)
                    .font(.obsidianHeadline)
                    .frame(width: 38, height: 38)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(customType.swiftUIColor.opacity(0.24), lineWidth: 0.5)
        )
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
