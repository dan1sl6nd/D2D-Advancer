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
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var isProcessing = false
    
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
            case .create: return "Schedule Appointment"
            case .edit: return "Save Changes"
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
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Lead Information Card (only for create mode)
                    if mode == .create, let lead = lead {
                        LeadInfoCard(lead: lead)
                    }
                    
                    // Appointment Details
                    AppointmentDetailsSection(
                        appointmentType: $appointmentType,
                        customAppointmentTypeId: $customAppointmentTypeId,
                        title: $title,
                        notes: $notes
                    )
                    
                    // Date & Time Section
                    DateTimeSection(
                        selectedDate: $selectedDate,
                        duration: $duration,
                        durationOptions: durationOptions,
                        endDate: endDate
                    )
                    
                    // Location Section
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
                .padding(.vertical, 20)
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
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
                        saveAppointment()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text(mode.saveButtonText)
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
                                            title.isEmpty || isProcessing ? Color.gray : Color.blue,
                                            title.isEmpty || isProcessing ? Color.gray.opacity(0.8) : Color.blue.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: title.isEmpty || isProcessing ? .clear : .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(title.isEmpty || isProcessing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(mode.processingText)
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                }
            }
        }
    }
    
    private func saveAppointment() {
        guard !title.isEmpty else { return }
        
        isProcessing = true
        
        Task {
            await MainActor.run {
                onSave()
                isProcessing = false
            }
        }
    }
}

// Use the same subviews from ScheduleAppointmentView
// Note: These are already defined in ScheduleAppointmentView.swift, so this creates duplicates.
// In a real implementation, these would be moved to a shared file.