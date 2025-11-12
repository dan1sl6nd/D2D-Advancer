import SwiftUI
import UIKit
import CoreData

struct AppointmentsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    @ObservedObject private var router = AppRouter.shared
    @State private var showingScheduleView = false
    @State private var selectedLead: Lead?
    @State private var selectedAppointment: Appointment?
    @State private var selectedView: AppointmentView = .active
    
    enum AppointmentView: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
        case cancelled = "Cancelled"
        
        var icon: String {
            switch self {
            case .active: return "calendar.badge.clock"
            case .completed: return "checkmark.circle"
            case .cancelled: return "xmark.circle"
            }
        }
    }
    
    var filteredAppointments: [Appointment] {
        switch selectedView {
        case .active:
            return appointmentManager.appointments
                .filter { $0.status != .completed && $0.status != .cancelled }
                .sorted { $0.startDate < $1.startDate }
        case .completed:
            return appointmentManager.appointments
                .filter { $0.status == .completed }
                .sorted { $0.startDate > $1.startDate }
        case .cancelled:
            return appointmentManager.appointments
                .filter { $0.status == .cancelled }
                .sorted { $0.startDate > $1.startDate }
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    safeAreaSpacer(geometry: geometry)
                    tabSelectionView
                    appointmentContentView
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingScheduleView = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingScheduleView) {
                SelectLeadForAppointmentView { lead in
                    selectedLead = lead
                    showingScheduleView = false
                }
            }
            .sheet(item: $selectedLead) { lead in
                ScheduleAppointmentView(lead: lead)
            }
            .sheet(item: $selectedAppointment) { appointment in
                AppointmentDetailView(appointmentId: appointment.id)
            }
            .onAppear {
                print("🗓️ AppointmentsView appeared - listener already active")
            }
            .onChange(of: router.targetAppointmentID) { _, newValue in
                guard let id = newValue else { return }
                if let appt = appointmentManager.appointments.first(where: { $0.id == id }) {
                    selectedAppointment = appt
                }
                router.targetAppointmentID = nil
            }
        }
    }
    
    // MARK: - Extracted View Components
    
    private func safeAreaSpacer(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.systemBackground).opacity(0.98)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: max((geometry.safeAreaInsets.top.isNaN ? 0 : geometry.safeAreaInsets.top) + 10, 60))
    }
    
    private var tabSelectionView: some View {
        HStack(spacing: 0) {
            ForEach(AppointmentView.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedView = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(selectedView == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedView == tab ? Color.blue : Color.clear)
                                .opacity(selectedView == tab ? 1 : 0)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(tab.rawValue) appointments")
                .accessibilityHint("Show \(tab.rawValue.lowercased()) appointments")
                .accessibilityAddTraits(selectedView == tab ? [.isSelected] : [])
                .accessibilityRemoveTraits(.isImage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appointment filter tabs")
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.tertiarySystemBackground))
                .padding(.horizontal, 12)
        )
    }
    
    private var appointmentContentView: some View {
        Group {
            if filteredAppointments.isEmpty {
                emptyStateView
            } else {
                appointmentScrollView
            }
        }
    }
    
    private var appointmentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredAppointments) { appointment in
                    AppointmentInteractiveRowView(
                        appointment: appointment,
                        onTap: { selectedAppointment = appointment },
                        onComplete: { updateAppointmentStatus(appointment, to: .completed) },
                        onCancel: { updateAppointmentStatus(appointment, to: .cancelled) },
                        onReactivate: { updateAppointmentStatus(appointment, to: .scheduled) },
                        onDelete: { deleteAppointment(appointment) }
                    )
                    .onLongPressGesture {
                        handleLongPressDelete(appointment)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func updateAppointmentStatus(_ appointment: Appointment, to status: Appointment.AppointmentStatus) {
        Task {
            var updatedAppointment = appointment
            updatedAppointment.status = status
            _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
        }
    }
    
    private func deleteAppointment(_ appointment: Appointment) {
        Task {
            await AppointmentManager.shared.deleteAppointment(appointment)
        }
    }
    
    private func handleLongPressDelete(_ appointment: Appointment) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        let alert = UIAlertController(
            title: "Delete Appointment",
            message: "Delete appointment '\(appointment.title)'?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            deleteAppointment(appointment)
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func deleteAppointments(offsets: IndexSet) {
        withAnimation {
            offsets.map { filteredAppointments[$0] }.forEach { appointment in
                // Use the appointment manager's delete function
                Task {
                    await appointmentManager.deleteAppointment(appointment)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: selectedView.icon)
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                )
            
            VStack(spacing: 8) {
                Text("No \(selectedView.rawValue.lowercased()) appointments")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(emptyMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowSeparator(.hidden)
    }
    
    private var emptyMessage: String {
        switch selectedView {
        case .active:
            return "Start scheduling appointments with your customers to keep track of installations and follow-ups."
        case .completed:
            return "Completed appointments will appear here after you mark them as finished."
        case .cancelled:
            return "Cancelled appointments will appear here when you cancel scheduled appointments."
        }
    }
    
}

// MARK: - AppointmentInteractiveRowView

struct AppointmentInteractiveRowView: View {
    let appointment: Appointment
    let onTap: () -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void
    let onReactivate: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var associatedLead: Lead?
    @State private var refreshId = UUID()
    @State private var showingCalendarEditor = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Appointment type icon circle
            Circle()
                .fill(appointment.displayColor(using: customTypeManager.customTypes))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: appointment.displayIcon(using: customTypeManager.customTypes))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appointment.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    // Quick action: Open in Maps (location)
                    if !appointment.location.isEmpty {
                        Button(action: {
                            openMaps(for: appointment.location)
                        }) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.orange)
                        .accessibilityLabel("Open in Maps")
                    }
                    
                    // Quick action: Calendar (add or open)
                    Button(action: {
                        if (appointment.calendarEventId ?? "").isEmpty {
                            addToCalendar(appointment)
                        } else {
                            openCalendarDate(appointment.startDate)
                        }
                    }) {
                        Image(systemName: (appointment.calendarEventId ?? "").isEmpty ? "calendar.badge.plus" : "calendar")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    .accessibilityLabel((appointment.calendarEventId ?? "").isEmpty ? "Add to Calendar" : "Open in Calendar")
                    
                    // Status badge
                    AppointmentStatusBadge(status: appointment.status)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Status")
                    .accessibilityValue(appointment.status.rawValue)
                }
                
                // Date and time
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("\(appointment.startDate.formatted(.dateTime.month().day())) at \(appointment.startDate.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Date and time")
                .accessibilityValue("\(appointment.startDate.formatted(.dateTime.month().day())) at \(appointment.startDate.formatted(.dateTime.hour().minute()))")
                
                HStack {
                    Text(appointment.displayName(using: customTypeManager.customTypes))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(appointment.displayColor(using: customTypeManager.customTypes).opacity(0.15))
                        )
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("View Details", systemImage: "eye")
            }
            
            Divider()
            
            // Status toggle actions based on current status
            if appointment.status == .scheduled || appointment.status == .confirmed {
                Button {
                    onComplete()
                } label: {
                    Label("Mark as Completed", systemImage: "checkmark.circle")
                }
                
                Button {
                    onCancel()
                } label: {
                    Label("Cancel Appointment", systemImage: "xmark.circle")
                }
            } else if appointment.status == .cancelled || appointment.status == .completed {
                Button {
                    onReactivate()
                } label: {
                    Label("Reactivate Appointment", systemImage: "arrow.clockwise")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Appointment", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            loadAssociatedLead()
        }
        .onChange(of: customTypeManager.customTypes) {
            refreshId = UUID()
        }
        .id(refreshId)
    }
    
    private func addToCalendar(_ appt: Appointment) {
        CalendarService.shared.requestAccessIfNeeded { granted in
            guard granted else {
                print("❌ Calendar access not granted")
                return
            }
            let eventId = CalendarService.shared.createOrUpdateEvent(for: appt)
            if let id = eventId {
                Task { @MainActor in
                    if let idx = AppointmentManager.shared.appointments.firstIndex(where: { $0.id == appt.id }) {
                        var updated = AppointmentManager.shared.appointments[idx]
                        updated.calendarEventId = id
                        AppointmentManager.shared.appointments[idx] = updated
                        await AppointmentManager.shared.syncAppointmentToFirebase(updated)
                    }
                }
            } else {
                print("❌ Failed to create calendar event")
            }
        }
    }

    private func openMaps(for location: String) {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func openCalendarDate(_ date: Date) {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(seconds)") {
            UIApplication.shared.open(url)
        }
    }
    
    

    private func loadAssociatedLead() {
        guard let leadId = appointment.leadId else { return }
        
        let request: NSFetchRequest<Lead> = Lead.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        request.fetchLimit = 1
        
        do {
            let leads = try viewContext.fetch(request)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }
}

// MARK: - AppointmentRowView (Legacy)

struct AppointmentRowView: View {
    let appointment: Appointment
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var associatedLead: Lead?
    @State private var refreshId = UUID()
    
    var body: some View {
        HStack(spacing: 16) {
            // Appointment type icon circle
            Circle()
                .fill(appointment.displayColor(using: customTypeManager.customTypes))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: appointment.displayIcon(using: customTypeManager.customTypes))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appointment.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    // Status badge
                    AppointmentStatusBadge(status: appointment.status)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Status")
                    .accessibilityValue(appointment.status.rawValue)
                }
                
                // Date and time
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("\(appointment.startDate.formatted(.dateTime.month().day())) at \(appointment.startDate.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Date and time")
                .accessibilityValue("\(appointment.startDate.formatted(.dateTime.month().day())) at \(appointment.startDate.formatted(.dateTime.hour().minute()))")
                
                HStack {
                    Text(appointment.displayName(using: customTypeManager.customTypes))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(appointment.displayColor(using: customTypeManager.customTypes).opacity(0.15))
                        )
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .onAppear {
            loadAssociatedLead()
        }
        .onChange(of: customTypeManager.customTypes) {
            refreshId = UUID()
        }
        .id(refreshId)
    }
    
    private func loadAssociatedLead() {
        guard let leadId = appointment.leadId else { return }
        
        let request: NSFetchRequest<Lead> = Lead.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        request.fetchLimit = 1
        
        do {
            let leads = try viewContext.fetch(request)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }
}


struct EmptyAppointmentsView: View {
    let selectedView: AppointmentsView.AppointmentView
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: selectedView.icon)
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No \(selectedView.rawValue.lowercased()) appointments")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(emptyMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptyMessage: String {
        switch selectedView {
        case .active:
            return "Start scheduling appointments with your customers to keep track of installations and follow-ups."
        case .completed:
            return "Completed appointments will appear here after you mark them as finished."
        case .cancelled:
            return "Cancelled appointments will appear here when you cancel scheduled appointments."
        }
    }
}

struct AppointmentCard: View {
    let appointment: Appointment
    let viewContext: NSManagedObjectContext
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingDetails = false
    @State private var associatedLead: Lead?
    @State private var showingLeadDetail = false
    @State private var refreshId = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type and status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: appointment.displayIcon(using: customTypeManager.customTypes))
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                    
                    Text(appointment.displayName(using: customTypeManager.customTypes))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                }
                
                Spacer()
                
                AppointmentStatusBadge(status: appointment.status)
            }
            
            // Title
            Text(appointment.title)
                .font(.headline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
            
            // Date and time
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appointment.startDate.formatted(.dateTime.day().month().year()))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("\(appointment.startDate.formatted(.dateTime.hour().minute())) - \(appointment.endDate.formatted(.dateTime.hour().minute()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Location
            if !appointment.location.isEmpty {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text(appointment.location)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                }
            }
            
            // Notes preview
            if !appointment.notes.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text(appointment.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                }
            }
            
            // Customer info
            if let lead = associatedLead {
                HStack {
                    Image(systemName: "person")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text(lead.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("View Lead") {
                        showingLeadDetail = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            // Action buttons
            HStack(spacing: 8) {
                Button("Details") {
                    showingDetails = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if appointment.status == .scheduled || appointment.status == .confirmed {
                    Button("Complete") {
                        markComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .foregroundColor(.white)
                    .background(.green)
                    
                    Button("Cancel") {
                        markCancelled()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                } else if appointment.status == .completed || appointment.status == .cancelled {
                    Button("Reactivate") {
                        reactivateAppointment()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.blue)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            loadAssociatedLead()
        }
        .onChange(of: customTypeManager.customTypes) {
            refreshId = UUID()
        }
        .id(refreshId)
        .sheet(isPresented: $showingDetails) {
            AppointmentDetailView(appointmentId: appointment.id)
        }
        .sheet(isPresented: $showingLeadDetail) {
            if let lead = associatedLead {
                LeadDetailView(lead: lead)
            }
        }
    }
    
    private func loadAssociatedLead() {
        guard let leadId = appointment.leadId else { return }
        
        let request: NSFetchRequest<Lead> = Lead.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        request.fetchLimit = 1
        
        do {
            let leads = try viewContext.fetch(request)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }
    
    private func markComplete() {
        var updatedAppointment = appointment
        updatedAppointment.status = .completed
        
        Task {
            await appointmentManager.updateAppointment(updatedAppointment)
        }
    }
    
    private func markCancelled() {
        var updatedAppointment = appointment
        updatedAppointment.status = .cancelled
        
        Task {
            await appointmentManager.updateAppointment(updatedAppointment)
        }
    }
    
    private func reactivateAppointment() {
        var updatedAppointment = appointment
        updatedAppointment.status = .scheduled
        
        Task {
            await appointmentManager.updateAppointment(updatedAppointment)
        }
    }
    
}


struct SelectLeadForAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.name, ascending: true)],
        predicate: NSPredicate(format: "status IN %@", ["interested", "scheduled", "converted"]),
        animation: .default
    ) private var eligibleLeads: FetchedResults<Lead>
    
    @State private var searchText = ""
    let onLeadSelected: (Lead) -> Void
    
    var filteredLeads: [Lead] {
        if searchText.isEmpty {
            return Array(eligibleLeads)
        } else {
            return eligibleLeads.filter { lead in
                lead.displayName.localizedCaseInsensitiveContains(searchText) ||
                (lead.address?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchText)
                    .padding(.horizontal, 16)
                
                if filteredLeads.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No eligible leads found")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Only interested, scheduled, or converted leads can have appointments scheduled.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredLeads, id: \.id) { lead in
                        LeadSelectionRow(lead: lead) {
                            onLeadSelected(lead)
                        }
                    }
                }
            }
            .navigationTitle("Select Customer")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based cancel button
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
}

struct LeadSelectionRow: View {
    let lead: Lead
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let address = lead.address {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    LeadStatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LeadStatusBadge: View {
    let status: LeadStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(8)
    }
}

struct AppointmentDetailView: View {
    let appointmentId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    @State private var showingEditView = false
    @State private var associatedLead: Lead?
    @State private var showingLeadDetail = false
    @State private var showingCalendarEditor = false
    @State private var refreshId = UUID()
    
    private var appointment: Appointment? {
        appointmentManager.appointments.first { $0.id == appointmentId }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        if let appointment = appointment {
                            // Appointment Header Card
                            appointmentHeaderCard(appointment: appointment)
                            
                            // Date & Time Card
                            dateTimeCard(appointment: appointment)
                            
                            // Location Card
                            if !appointment.location.isEmpty {
                                locationCard(appointment: appointment)
                            }
                            
                            // Customer Information Card
                            if let lead = associatedLead {
                                customerInformationCard(lead: lead)
                            }
                            
                            // Notes Card
                            if !appointment.notes.isEmpty {
                                notesCard(appointment: appointment)
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "calendar.badge.exclamationmark")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text("Appointment Not Found")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("This appointment may have been deleted.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Appointment Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                VStack(spacing: 12) {
                    // Status action buttons (only for active appointments)
                    if let appointment = appointment, appointment.status == .scheduled || appointment.status == .confirmed {
                        HStack(spacing: 12) {
                            // Complete button
                            Button(action: {
                                Task {
                                    var updatedAppointment = appointment
                                    updatedAppointment.status = .completed
                                    _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                    Text("Mark Complete")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                            }
                            
                            // Cancel button
                            Button(action: {
                                Task {
                                    var updatedAppointment = appointment
                                    updatedAppointment.status = .cancelled
                                    _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                    Text("Cancel")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                            }
                        }
                    }
                    
                    // Action buttons in organized sections
                    VStack(spacing: 16) {
                        // Primary actions row
                        HStack(spacing: 12) {
                            Button(action: {
                                showingEditView = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "pencil")
                                        .font(.callout)
                                    Text("Edit")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(UIColor.secondarySystemBackground))
                                )
                            }

                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.callout)
                                    Text("Done")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue)
                                )
                            }
                        }

                        // Calendar actions row (if applicable)
                        if let appointment = appointment {
                            if (appointment.calendarEventId ?? "").isEmpty == false {
                                HStack(spacing: 12) {
                                    Button(action: { openCalendarDate(appointment.startDate) }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "calendar")
                                                .font(.callout)
                                            Text("View")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.blue)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                    }

                                    Button(action: { showCalendarEditor(appointment) }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "pencil.and.outline")
                                                .font(.callout)
                                            Text("Edit Event")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.purple)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.purple.opacity(0.1))
                                        )
                                    }
                                }
                            } else {
                                Button(action: { addToCalendar(appointment) }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(.callout)
                                        Text("Add to Calendar")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                }
                            }
                        }

                        // Reactivate button (for completed or cancelled appointments)
                        if let appointment = appointment, appointment.status == .completed || appointment.status == .cancelled {
                            Button(action: {
                                Task {
                                    var updatedAppointment = appointment
                                    updatedAppointment.status = .scheduled
                                    _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.callout)
                                    Text("Reactivate Appointment")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(0.1))
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(isPresented: $showingEditView) {
                if let appointment = appointment {
                    EditAppointmentView(appointment: appointment)
                }
            }
            .sheet(isPresented: $showingCalendarEditor) {
                if let appointment = appointment {
                    CalendarEventEditView(appointment: appointment) { eventId in
                        // onSaved
                        Task { @MainActor in
                            if let idx = AppointmentManager.shared.appointments.firstIndex(where: { $0.id == appointment.id }) {
                                var updated = AppointmentManager.shared.appointments[idx]
                                updated.calendarEventId = eventId
                                AppointmentManager.shared.appointments[idx] = updated
                                await AppointmentManager.shared.syncAppointmentToFirebase(updated)
                            }
                            showingCalendarEditor = false
                        }
                    } onCancel: {
                        showingCalendarEditor = false
                    }
                }
            }
            .sheet(isPresented: $showingLeadDetail) {
                if let lead = associatedLead {
                    LeadDetailView(lead: lead)
                }
            }
            .onAppear {
                loadAssociatedLead()
            }
            .onChange(of: customTypeManager.customTypes) {
                refreshId = UUID()
            }
            .id(refreshId)
        }
    }

    private func openCalendarDate(_ date: Date) {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(seconds)") {
            UIApplication.shared.open(url)
        }
    }

    private func openMaps(for location: String) {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func appointmentHeaderCard(appointment: Appointment) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Appointment Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Type and Status
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: appointment.displayIcon(using: customTypeManager.customTypes))
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                        .font(.title2)
                        .frame(width: 24)
                    
                    Text(appointment.displayName(using: customTypeManager.customTypes))
                        .font(.headline)
                        .foregroundColor(appointment.displayColor(using: customTypeManager.customTypes))
                    
                    Spacer()
                    
                    AppointmentStatusBadge(status: appointment.status)
                }
                
                Text(appointment.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
    
    private func dateTimeCard(appointment: Appointment) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Date & Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appointment.startDate.formatted(.dateTime.day().month().year().weekday(.wide)))
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("\(appointment.startDate.formatted(.dateTime.hour().minute())) - \(appointment.endDate.formatted(.dateTime.hour().minute()))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                let duration = appointment.endDate.timeIntervalSince(appointment.startDate)
                let safeDuration = duration.isNaN || duration < 0 ? 3600 : duration // Default to 1 hour if invalid
                let hours = Int(safeDuration) / 3600
                let minutes = Int(safeDuration) % 3600 / 60
                let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    Text("Duration: \(durationText)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
    
    private func locationCard(appointment: Appointment) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Location")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                if !appointment.location.isEmpty {
                    Button("Open in Maps") {
                        openMaps(for: appointment.location)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(appointment.location)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
    
    private func customerInformationCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Customer Information")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View Lead") {
                    showingLeadDetail = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Name and Address
                VStack(alignment: .leading, spacing: 8) {
                    if let name = lead.name, !name.isEmpty {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(name)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                    }
                    
                    if let address = lead.address, !address.isEmpty {
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(address)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                }
                
                // Contact Information
                VStack(alignment: .leading, spacing: 8) {
                    if let phone = lead.phone, !phone.isEmpty {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(phone)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                if let url = URL(string: "tel:\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Image(systemName: "phone.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            }
                        }
                    }
                    
                    if let email = lead.email, !email.isEmpty {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(email)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                if let url = URL(string: "mailto:\(email)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Image(systemName: "envelope.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                        }
                    }
                }
                
                // Lead Status and Priority
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        LeadStatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                    }
                    
                    if lead.priority > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Priority")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                            
                            HStack {
                                ForEach(1...Int(lead.priority), id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                
                // Financial Information
                if lead.price > 0 || lead.estimatedValue > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        if lead.price > 0 {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 20)
                                
                                Text("Price: $\(lead.price, specifier: "%.2f")")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                        }
                        
                        if lead.estimatedValue > 0 && lead.estimatedValue != lead.price {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                
                                Text("Estimated: $\(lead.estimatedValue, specifier: "%.2f")")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                        }
                    }
                }
                
                // Additional Information
                VStack(alignment: .leading, spacing: 8) {
                    if let source = lead.source, !source.isEmpty {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text("Source: \(source)")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                    
                    if lead.visitCount > 0 {
                        HStack {
                            Image(systemName: "person.2.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text("Visits: \(lead.visitCount)")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                    
                    if let lastContact = lead.lastContactDate {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text("Last Contact: \(lastContact.formatted(.dateTime.month().day().year()))")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                }
                
                // Tags
                if let tags = lead.tags, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        Text(tags)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
    
    private func notesCard(appointment: Appointment) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Notes")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            Text(appointment.notes)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.leading, 32)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
    
    private func loadAssociatedLead() {
        guard let appointment = appointment,
              let leadId = appointment.leadId else { return }

        let request: NSFetchRequest<Lead> = Lead.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        request.fetchLimit = 1

        do {
            let leads = try viewContext.fetch(request)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }

    private func showCalendarEditor(_ appt: Appointment) {
        CalendarService.shared.requestAccessIfNeeded { granted in
            DispatchQueue.main.async {
                if granted {
                    showingCalendarEditor = true
                } else {
                    print("❌ Calendar access not granted for editor")
                }
            }
        }
    }

    private func addToCalendar(_ appt: Appointment) {
        CalendarService.shared.requestAccessIfNeeded { granted in
            guard granted else {
                print("❌ Calendar access not granted")
                return
            }
            let eventId = CalendarService.shared.createOrUpdateEvent(for: appt)
            if let id = eventId {
                Task { @MainActor in
                    if let idx = AppointmentManager.shared.appointments.firstIndex(where: { $0.id == appt.id }) {
                        var updated = AppointmentManager.shared.appointments[idx]
                        updated.calendarEventId = id
                        AppointmentManager.shared.appointments[idx] = updated
                        await AppointmentManager.shared.syncAppointmentToFirebase(updated)
                    }
                }
            } else {
                print("❌ Failed to create calendar event")
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            content
                .padding(.leading, 32)
        }
    }
}

struct EditAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appointmentManager = AppointmentManager.shared
    
    let appointment: Appointment
    
    @State private var appointmentType: Appointment.AppointmentType
    @State private var customAppointmentTypeId: String?
    @State private var title: String
    @State private var notes: String
    @State private var selectedDate: Date
    @State private var duration: TimeInterval
    @State private var location: String
    @State private var associatedLead: Lead?
    
    init(appointment: Appointment) {
        self.appointment = appointment
        self._appointmentType = State(initialValue: appointment.appointmentType)
        self._customAppointmentTypeId = State(initialValue: appointment.customAppointmentTypeId)
        self._title = State(initialValue: appointment.title)
        self._notes = State(initialValue: appointment.notes)
        self._selectedDate = State(initialValue: appointment.startDate)
        let calculatedDuration = appointment.endDate.timeIntervalSince(appointment.startDate)
        let safeDuration = calculatedDuration.isNaN || calculatedDuration < 0 ? 3600 : calculatedDuration
        self._duration = State(initialValue: safeDuration)
        self._location = State(initialValue: appointment.location)
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
        AppointmentFormView(
            appointmentType: $appointmentType,
            customAppointmentTypeId: $customAppointmentTypeId,
            title: $title,
            notes: $notes,
            selectedDate: $selectedDate,
            duration: $duration,
            location: $location,
            mode: .edit,
            lead: associatedLead,
            existingAppointment: appointment,
            onSave: {
                updateAppointment()
            },
            onCancel: {
                dismiss()
            }
        )
        .onAppear {
            loadAssociatedLead()
        }
    }
    
    private func loadAssociatedLead() {
        guard let leadId = appointment.leadId else { return }
        
        // Find the lead associated with this appointment
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        
        do {
            let leads = try context.fetch(fetchRequest)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }
    
    private func updateAppointment() {
        let endDate = selectedDate.addingTimeInterval(duration)
        
        let updatedAppointment = Appointment(
            id: appointment.id,
            title: title,
            notes: notes,
            startDate: selectedDate,
            endDate: endDate,
            location: location,
            leadId: appointment.leadId,
            calendarEventId: appointment.calendarEventId,
            appointmentType: appointmentType,
            customAppointmentTypeId: customAppointmentTypeId,
            status: appointment.status
        )
        
        Task {
            let success = await appointmentManager.updateAppointment(updatedAppointment)
            
            await MainActor.run {
                if success {
                    dismiss()
                } else {
                    // Error handling is managed by AppointmentManager
                    print("❌ Appointment update failed")
                }
            }
        }
    }
}

// MARK: - Edit Form Sections

struct EditAppointmentDetailsSection: View {
    @Binding var appointmentType: Appointment.AppointmentType
    @Binding var customAppointmentTypeId: String?
    @Binding var title: String
    @Binding var notes: String
    @ObservedObject private var customTypeManager = CustomAppointmentTypeManager.shared
    @State private var showingCustomTypeCreator = false
    
    private var allAppointmentTypes: [AppointmentTypeWrapper] {
        customTypeManager.allAppointmentTypes
    }
    
    private var selectedTypeWrapper: AppointmentTypeWrapper? {
        if let customId = customAppointmentTypeId {
            return allAppointmentTypes.first { 
                if case .customType(let custom) = $0 {
                    return custom.id == customId
                }
                return false
            }
        } else {
            return allAppointmentTypes.first {
                if case .defaultType(let defaultType) = $0 {
                    return defaultType == appointmentType
                }
                return false
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Appointment Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("New Type") {
                    showingCustomTypeCreator = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Appointment Type Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appointment Type")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 8)
                ], spacing: 8) {
                    ForEach(allAppointmentTypes) { typeWrapper in
                        EditAppointmentTypeChipWrapper(
                            typeWrapper: typeWrapper,
                            isSelected: isSelected(typeWrapper),
                            onTap: {
                                selectType(typeWrapper)
                            },
                            onDelete: typeWrapper.isCustom ? {
                                if case .customType(let custom) = typeWrapper {
                                    customTypeManager.deleteCustomType(custom)
                                }
                            } : nil
                        )
                        .clipped()
                    }
                }
                .clipped()
            }
            .clipped()
            
            // Title Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appointment Title")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                
                TextField("Enter appointment title", text: $title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
                    .clipped()
            }
            .clipped()
            
            // Notes Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .padding(12)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                        )
                    
                    if notes.isEmpty {
                        Text("Add appointment notes...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
        .clipped()
        .sheet(isPresented: $showingCustomTypeCreator) {
            CustomAppointmentTypeCreatorView()
        }
    }
    
    private func isSelected(_ typeWrapper: AppointmentTypeWrapper) -> Bool {
        switch typeWrapper {
        case .defaultType(let defaultType):
            return customAppointmentTypeId == nil && appointmentType == defaultType
        case .customType(let custom):
            return customAppointmentTypeId == custom.id
        }
    }
    
    private func selectType(_ typeWrapper: AppointmentTypeWrapper) {
        // Extract the lead name from existing title if it exists
        let leadNameSuffix = extractLeadNameFromTitle(title)
        
        switch typeWrapper {
        case .defaultType(let defaultType):
            appointmentType = defaultType
            customAppointmentTypeId = nil
            // Update title to match the appointment type, preserving lead name
            title = defaultType.rawValue + leadNameSuffix
        case .customType(let custom):
            customAppointmentTypeId = custom.id
            // Keep the appointmentType as a fallback
            // Update title to match the custom type, preserving lead name
            title = custom.name + leadNameSuffix
        }
    }
    
    private func extractLeadNameFromTitle(_ currentTitle: String) -> String {
        // Look for pattern " - [Lead Name]" at the end of the title
        if let dashIndex = currentTitle.lastIndex(of: "-") {
            let afterDash = currentTitle[currentTitle.index(after: dashIndex)...].trimmingCharacters(in: .whitespaces)
            
            // Only treat it as a lead name suffix if there's content after the dash
            if !afterDash.isEmpty {
                return " - " + afterDash
            }
        }
        return ""
    }
}

struct EditAppointmentTypeChipWrapper: View {
    let typeWrapper: AppointmentTypeWrapper
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        Image(systemName: typeWrapper.icon)
                            .font(.title3)
                        
                        Text(typeWrapper.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    
                    if typeWrapper.isCustom, let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .background(Color.white, in: Circle())
                        }
                        .offset(x: 8, y: -8)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? typeWrapper.color.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
            )
            .foregroundColor(isSelected ? typeWrapper.color : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(typeWrapper.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EditAppointmentTypeChip: View {
    let type: Appointment.AppointmentType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.title3)
                
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? type.color.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
            )
            .foregroundColor(isSelected ? type.color : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(type.color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EditDateTimeSection: View {
    @Binding var selectedDate: Date
    @Binding var duration: TimeInterval
    let durationOptions: [(String, TimeInterval)]
    let endDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Date & Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Start Date & Time Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Start Date & Time")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Duration Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Menu {
                    ForEach(Array(durationOptions.enumerated()), id: \.offset) { _, option in
                        Button(action: {
                            duration = option.1
                        }) {
                            HStack {
                                Text(option.0)
                                if duration == option.1 {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "hourglass")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text(durationOptions.first(where: { $0.1 == duration })?.0 ?? "1 hour")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
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
            }
            
            // End Time Display Section
            VStack(alignment: .leading, spacing: 12) {
                Text("End Time")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    Text(endDate.formatted(.dateTime.day().month().year().hour().minute()))
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground).opacity(0.5))
                .cornerRadius(10)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
}

struct EditLocationSection: View {
    @Binding var location: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Location")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Location Input Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appointment Location")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    TextField("Enter appointment location", text: $location)
                        .font(.body)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
                
                Text("Optional: Add specific location details for this appointment")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor.tertiarySystemBackground),
                            Color(UIColor.tertiarySystemBackground).opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        )
    }
}


#Preview {
    AppointmentsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
