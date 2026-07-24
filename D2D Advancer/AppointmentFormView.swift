import SwiftUI

struct AppointmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    
    // Form data binding
    @Binding var appointmentType: Appointment.AppointmentType
    @Binding var customAppointmentTypeId: String?
    @Binding var title: String
    @Binding var notes: String
    @Binding var selectedDate: Date
    @Binding var duration: TimeInterval
    @Binding var location: String
    
    // Configuration
    let mode: AppointmentFormMode
    let lead: Lead?
    let existingAppointment: Appointment?
    let onSave: () async -> Bool
    let onCancel: () -> Void
    
    @State private var isProcessing = false
    @State private var formErrorMessage: String?
    
    enum AppointmentFormMode {
        case create
        case edit
        
        var navigationTitle: String {
            switch self {
            case .create: return "Schedule Appointment"
            case .edit: return "Edit Appointment"
            }
        }
        
        var saveButtonText: String {
            switch self {
            case .create: return "Schedule"
            case .edit: return "Save"
            }
        }
        
        var processingText: String {
            switch self {
            case .create: return "Scheduling Appointment..."
            case .edit: return "Saving Changes..."
            }
        }

    }
    
    private var endDate: Date {
        selectedDate.addingTimeInterval(duration)
    }
    
    private var durationOptions: [(String, TimeInterval)] {
        [
            ("30 minutes", 30 * 60),
            ("1 hour", 60 * 60),
            ("1.5 hours", 90 * 60),
            ("2 hours", 120 * 60),
            ("3 hours", 180 * 60),
            ("Half day", 4 * 60 * 60),
            ("Full day", 8 * 60 * 60)
        ]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if mode == .create, let lead = lead {
                        LeadInfoCard(lead: lead)
                    }

                    AppointmentDetailsSection(
                        appointmentType: $appointmentType,
                        customAppointmentTypeId: $customAppointmentTypeId,
                        title: $title,
                        notes: $notes
                    )

                    DateTimeSection(
                        selectedDate: $selectedDate,
                        duration: $duration,
                        durationOptions: durationOptions,
                        endDate: endDate
                    )

                    if let lead = lead {
                        LocationSection(
                            location: $location, 
                            lead: lead
                        )
                    } else {
                        EditLocationSection(location: $location)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier(mode == .create ? "appointmentCreateForm" : "appointmentEditForm")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                mode.navigationTitle,
                backButtonAccessibilityIdentifier: mode == .create ? "appointmentCreateBackButton" : "appointmentEditBackButton",
                onBack: onCancel
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: title.isEmpty || isProcessing,
                    primaryAccessibilityIdentifier: mode == .create ? "appointmentScheduleSaveButton" : "appointmentEditSaveButton",
                    secondaryAccessibilityIdentifier: mode == .create ? "appointmentScheduleCancelButton" : "appointmentEditCancelButton",
                    primaryAction: saveAppointment,
                    secondaryAction: onCancel,
                    primaryLabel: {
                        Label(mode.saveButtonText, systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color.electricViolet)
                        Text(mode.processingText)
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                    }
                    .padding(24)
                    .background(Color.obsidianSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .obsidianModalBackground()
            .alert(
                "Appointment not saved",
                isPresented: Binding(
                    get: { formErrorMessage != nil },
                    set: { if !$0 { formErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(formErrorMessage ?? "Please try again.")
            }
        }
    }
    
    private func saveAppointment() {
        guard !title.isEmpty else { return }
        
        isProcessing = true
        
        Task {
            let didSave = await onSave()
            await MainActor.run {
                isProcessing = false
                if !didSave {
                    formErrorMessage = appointmentManager.errorMessage
                        ?? "Could not save the appointment. Check the details and try again."
                }
            }
        }
    }
}

// Use the same subviews from ScheduleAppointmentView
// Note: These are already defined in ScheduleAppointmentView.swift, so this creates duplicates.
// In a real implementation, these would be moved to a shared file.
