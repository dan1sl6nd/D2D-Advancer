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
    @ObservedObject private var paywallManager = PaywallManager.shared
    
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
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    safeAreaSpacer(geometry: geometry)
                    ObsidianHeaderView("Appointments") {
                        ObsidianCompactIconButton(
                            icon: "plus",
                            accessibilityLabel: "Schedule appointment"
                        ) {
                            guard paywallManager.gateAction() else { return }
                            showingScheduleView = true
                        }
                        .accessibilityIdentifier("appointmentsScheduleButton")
                    }
                    tabSelectionView
                    appointmentContentView
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color.obsidianBlack)
            .accessibilityIdentifier("appointmentsScreen")
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
            .fill(Color.obsidianBlack)
            .frame(height: geometry.safeAreaInsets.top)
    }
    
    private var tabSelectionView: some View {
        HStack(spacing: 4) {
            ForEach(AppointmentView.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedView = tab
                    }
                }) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.obsidianFootnote)
                        .labelStyle(.titleAndIcon)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(selectedView == tab ? .white : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedView == tab ? Color.electricViolet : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(tab.rawValue) appointments")
                .accessibilityHint("Show \(tab.rawValue.lowercased()) appointments")
                .accessibilityAddTraits(selectedView == tab ? [.isSelected] : [])
                .accessibilityRemoveTraits(.isImage)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.obsidianSurface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appointment filter tabs")
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(Color.obsidianBlack)
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
            .padding(.bottom, 12)
        }
    }
    
    private func updateAppointmentStatus(_ appointment: Appointment, to status: Appointment.AppointmentStatus) {
        guard paywallManager.gateAction() else { return }
        Task {
            var updatedAppointment = appointment
            updatedAppointment.status = status
            _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
        }
    }

    private func deleteAppointment(_ appointment: Appointment) {
        guard paywallManager.gateAction() else { return }
        Task {
            await AppointmentManager.shared.deleteAppointment(appointment)
        }
    }

    private func handleLongPressDelete(_ appointment: Appointment) {
        guard paywallManager.gateAction() else { return }
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
        ObsidianEmptyState(
            icon: selectedView.icon,
            title: "No \(selectedView.rawValue.lowercased()) appointments",
            message: emptyMessage,
            actionTitle: selectedView == .active ? "Schedule" : nil,
            actionIcon: "plus",
            action: selectedView == .active ? {
                guard paywallManager.gateAction() else { return }
                showingScheduleView = true
            } : nil
        )
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
        let accent = appointment.displayColor(using: customTypeManager.customTypes)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(
                    icon: appointment.displayIcon(using: customTypeManager.customTypes),
                    tint: accent,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(appointment.title)
                            .font(.themeTitle)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)

                        Spacer(minLength: 6)

                        AppointmentStatusBadge(status: appointment.status)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Status")
                            .accessibilityValue(appointment.status.rawValue)
                    }

                    Text("\(appointment.startDate.formatted(.dateTime.month().day())) at \(appointment.startDate.formatted(.dateTime.hour().minute()))")
                        .font(.obsidianFootnote)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(1)

                    if !appointment.location.isEmpty {
                        Label(appointment.location, systemImage: "location.fill")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    } else if let associatedLead {
                        Label(associatedLead.displayName, systemImage: "person.fill")
                            .font(.micro)
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                Label(appointment.displayName(using: customTypeManager.customTypes), systemImage: "tag.fill")
                    .font(.micro)
                    .foregroundColor(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.12)))

                Spacer(minLength: 0)

                if !appointment.location.isEmpty {
                    rowActionButton(
                        icon: "mappin.and.ellipse",
                        tint: Color.statusNotHome,
                        accessibilityLabel: "Open in Maps"
                    ) {
                        openMaps(for: appointment.location)
                    }
                }

                rowActionButton(
                    icon: (appointment.calendarEventId ?? "").isEmpty ? "calendar.badge.plus" : "calendar",
                    tint: Color.electricViolet,
                    accessibilityLabel: (appointment.calendarEventId ?? "").isEmpty ? "Add to Calendar" : "Open in Calendar"
                ) {
                    if (appointment.calendarEventId ?? "").isEmpty {
                        addToCalendar(appointment)
                    } else {
                        openCalendarDate(appointment.startDate)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
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

    private func rowActionButton(
        icon: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.micro)
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabel)
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
                        _ = await AppointmentManager.shared.updateAppointment(updated)
                    }
                }
            } else {
                print("❌ Failed to create calendar event")
            }
        }
    }

    private func openMaps(for location: String) {
        Utilities.openMapsSearch(query: location)
    }

    private func openCalendarDate(_ date: Date) {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(seconds)") {
            UIApplication.shared.open(url)
        }
    }
    
    

    private func loadAssociatedLead() {
        guard let leadId = appointment.leadId else { return }
        
        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
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

// MARK: - Appointment Lead Selection

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ObsidianScreenTitle(
                        title: "Select Customer",
                        subtitle: "Pick an interested, scheduled, or converted lead to create the appointment.",
                        icon: "calendar.badge.plus"
                    )

                    ObsidianSectionCard(
                        title: "Find Lead",
                        icon: "magnifyingglass",
                        subtitle: "\(filteredLeads.count) eligible \(filteredLeads.count == 1 ? "lead" : "leads")"
                    ) {
                        LeadFormTextField(
                            title: "Search",
                            placeholder: "Name or address",
                            text: $searchText,
                            icon: "magnifyingglass"
                        )
                    }

                    if filteredLeads.isEmpty {
                        ObsidianEmptyState(
                            icon: "person.3.fill",
                            title: "No eligible leads",
                            message: "Only interested, scheduled, or converted leads can have appointments scheduled."
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredLeads, id: \.id) { lead in
                                LeadSelectionRow(lead: lead) {
                                    onLeadSelected(lead)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 96)
            }
            .background(Color.obsidianBlack.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    dismiss()
                }) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Color.obsidianBlack
                        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: -3)
                )
            }
        }
        .presentationBackground(Color.obsidianBlack)
    }
}

struct LeadSelectionRow: View {
    let lead: Lead
    let onTap: () -> Void
    
    var body: some View {
        let status = LeadStatus.from(leadStatus: lead.leadStatus)

        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ObsidianIconTile(icon: "person.fill", tint: status.color, size: 42)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lead.displayName)
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        LeadStatusBadge(status: status)
                    }

                    if let address = lead.address, !address.isEmpty {
                        Label(address, systemImage: "location.fill")
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                            .lineLimit(2)
                    }

                    Text("Schedule appointment")
                        .font(.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.electricViolet)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color.obsidianSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LeadStatusBadge: View {
    let status: LeadStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.micro)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .clipShape(Capsule())
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
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAppointment = false
    @State private var refreshId = UUID()
    
    private var appointment: Appointment? {
        appointmentManager.appointments.first { $0.id == appointmentId }
    }
    
    var body: some View {
        NavigationStack {
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
                                    .foregroundColor(Color.textSecondary)

                                Text("Appointment Not Found")
                                    .font(.obsidianHeadline)
                                    .foregroundColor(Color.textPrimary)

                                Text("This appointment may have been deleted.")
                                    .font(.obsidianBody)
                                    .foregroundColor(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color.obsidianBlack)
            }
            .navigationTitle("Appointment Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                appointmentDetailBottomBar
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
	                                _ = await AppointmentManager.shared.updateAppointment(updated)
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
            .alert("Delete Appointment?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAppointmentPermanently()
                }
            } message: {
                Text("This permanently removes the appointment, its reminder notifications, and any linked calendar event.")
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

    @ViewBuilder
    private var appointmentDetailBottomBar: some View {
        if let appointment {
            VStack(spacing: 8) {
                if appointment.status == .scheduled || appointment.status == .confirmed {
                    HStack(spacing: 8) {
                        appointmentActionButton(
                            title: "Cancel",
                            icon: "xmark",
                            tone: .danger
                        ) {
                            updateAppointmentStatus(appointment, to: .cancelled)
                        }

                        appointmentActionButton(
                            title: "Complete",
                            icon: "checkmark",
                            tone: .primary
                        ) {
                            updateAppointmentStatus(appointment, to: .completed)
                        }
                    }
                } else if appointment.status == .completed || appointment.status == .cancelled {
                    appointmentActionButton(
                        title: "Reactivate",
                        icon: "arrow.clockwise",
                        tone: .secondary
                    ) {
                        updateAppointmentStatus(appointment, to: .scheduled)
                    }
                }

                HStack(spacing: 8) {
                    appointmentActionButton(
                        title: "Delete",
                        icon: "trash",
                        tone: .danger,
                        disabled: isDeletingAppointment
                    ) {
                        showingDeleteConfirmation = true
                    }

                    appointmentActionButton(
                        title: "Edit",
                        icon: "pencil",
                        tone: .secondary
                    ) {
                        showingEditView = true
                    }

                    appointmentActionButton(
                        title: "Done",
                        icon: "checkmark",
                        tone: .primary
                    ) {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.obsidianElevated)
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: -3)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(Color.obsidianBlack.ignoresSafeArea(edges: .bottom))
        } else {
            appointmentActionButton(
                title: "Done",
                icon: "checkmark",
                tone: .primary
            ) {
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.obsidianBlack.ignoresSafeArea(edges: .bottom))
        }
    }

    private func appointmentActionButton(
        title: String,
        icon: String,
        tone: AppointmentActionTone,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .foregroundColor(tone.foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .background(tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(tone.borderColor, lineWidth: 1)
            )
            .opacity(disabled ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(title)
    }

    private enum AppointmentActionTone {
        case primary
        case secondary
        case danger

        var foregroundColor: Color {
            switch self {
            case .primary:
                return .white
            case .secondary:
                return Color.textPrimary
            case .danger:
                return Color.statusNotInterested
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary:
                return Color.electricViolet
            case .secondary:
                return Color.obsidianSurface
            case .danger:
                return Color.statusNotInterested.opacity(0.08)
            }
        }

        var borderColor: Color {
            switch self {
            case .primary:
                return Color.electricViolet.opacity(0.85)
            case .secondary:
                return Color.obsidianBorder.opacity(0.75)
            case .danger:
                return Color.statusNotInterested.opacity(0.4)
            }
        }
    }

    private func updateAppointmentStatus(_ appointment: Appointment, to status: Appointment.AppointmentStatus) {
        Task {
            var updatedAppointment = appointment
            updatedAppointment.status = status
            _ = await AppointmentManager.shared.updateAppointment(updatedAppointment)
        }
    }

    private func deleteAppointmentPermanently() {
        guard let appointment, !isDeletingAppointment else { return }

        isDeletingAppointment = true
        Task {
            let didDelete = await AppointmentManager.shared.deleteAppointment(appointment)
            await MainActor.run {
                isDeletingAppointment = false
                if didDelete {
                    dismiss()
                }
            }
        }
    }

    private func openCalendarDate(_ date: Date) {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(seconds)") {
            UIApplication.shared.open(url)
        }
    }

    private func openMaps(for location: String) {
        Utilities.openMapsSearch(query: location)
    }
    
    private func appointmentHeaderCard(appointment: Appointment) -> some View {
        let accent = appointment.displayColor(using: customTypeManager.customTypes)

        return HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(
                icon: appointment.displayIcon(using: customTypeManager.customTypes),
                tint: accent,
                size: 46,
                filled: true
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(appointment.title)
                        .font(.themeTitle)
                        .foregroundColor(Color.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 6)

                    AppointmentStatusBadge(status: appointment.status)
                }

                Text(appointment.displayName(using: customTypeManager.customTypes))
                    .font(.obsidianFootnote)
                    .foregroundColor(accent)
                    .lineLimit(1)

                Label(appointment.startDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()), systemImage: "clock")
                    .font(.micro)
                    .foregroundColor(Color.textMuted)
            }
        }
        .padding()
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.6), lineWidth: 0.5)
        )
    }
    
    private func dateTimeCard(appointment: Appointment) -> some View {
        LeadFormSectionCard(title: "Schedule", icon: "calendar.badge.clock") {
            VStack(spacing: 12) {
                ObsidianDetailRow(
                    title: "Date",
                    value: appointment.startDate.formatted(.dateTime.day().month().year().weekday(.wide)),
                    icon: "calendar",
                    tint: Color.electricViolet
                )

                ObsidianDetailRow(
                    title: "Time",
                    value: "\(appointment.startDate.formatted(.dateTime.hour().minute())) - \(appointment.endDate.formatted(.dateTime.hour().minute()))",
                    icon: "clock.fill",
                    tint: Color.statusNotHome
                )

                ObsidianDetailRow(
                    title: "Duration",
                    value: appointmentDurationText(appointment),
                    icon: "hourglass",
                    tint: Color.statusConverted
                )
            }
        }
    }
    
    private func locationCard(appointment: Appointment) -> some View {
        LeadFormSectionCard(title: "Location", icon: "map.fill") {
            VStack(spacing: 12) {
                ObsidianDetailRow(
                    title: "Address",
                    value: appointment.location,
                    icon: "mappin.circle.fill",
                    tint: Color.statusNotInterested,
                    valueLineLimit: 3
                )

                ObsidianActionTile(
                    title: "Open in Maps",
                    icon: "location.north.line.fill",
                    tint: Color.electricViolet
                ) {
                    openMaps(for: appointment.location)
                }
            }
        }
    }
    
    private func customerInformationCard(lead: Lead) -> some View {
        LeadFormSectionCard(title: "Customer", icon: "person.crop.circle.fill") {
            VStack(spacing: 12) {
                ObsidianDetailRow(
                    title: "Name",
                    value: lead.displayName,
                    icon: "person.fill",
                    tint: Color.electricViolet
                )

                if let address = lead.address, !address.isEmpty {
                    ObsidianDetailRow(
                        title: "Address",
                        value: address,
                        icon: "house.fill",
                        tint: Color.statusNotInterested,
                        valueLineLimit: 3
                    )
                }

                if let phone = lead.phone, !phone.isEmpty {
                    ObsidianDetailRow(
                        title: "Phone",
                        value: phone,
                        icon: "phone.fill",
                        tint: Color.statusInterested
                    ) {
                        Button {
                            Utilities.makePhoneCall(to: phone)
                        } label: {
                            Image(systemName: "phone.circle.fill")
                                .font(.obsidianAction)
                                .foregroundColor(Color.statusInterested)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Call customer")
                    }
                }

                if let email = lead.email, !email.isEmpty {
                    ObsidianDetailRow(
                        title: "Email",
                        value: email,
                        icon: "envelope.fill",
                        tint: Color.statusNotHome,
                        valueLineLimit: 1
                    ) {
                        Button {
                            Utilities.sendEmail(to: email)
                        } label: {
                            Image(systemName: "envelope.circle.fill")
                                .font(.obsidianAction)
                                .foregroundColor(Color.electricViolet)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Email customer")
                    }
                }

                HStack(spacing: 10) {
                    LeadStatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))

                    if lead.priority > 0 {
                        Label("Priority \(Int(lead.priority))", systemImage: "star.fill")
                            .font(.micro)
                            .foregroundColor(Color.statusNotHome)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.statusNotHome.opacity(0.12)))
                    }

                    Spacer(minLength: 0)
                }

                if lead.price > 0 {
                    ObsidianDetailRow(
                        title: "Sold Price",
                        value: lead.price.formatted(.currency(code: "CAD")),
                        icon: "dollarsign.circle.fill",
                        tint: Color.statusConverted
                    )
                } else if lead.estimatedValue > 0 {
                    ObsidianDetailRow(
                        title: "Estimated Value",
                        value: lead.estimatedValue.formatted(.currency(code: "CAD")),
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        tint: Color.statusConverted
                    )
                }

                ObsidianActionTile(
                    title: "View Full Lead",
                    subtitle: "Open customer details and all lead actions.",
                    icon: "arrow.up.forward.app.fill",
                    tint: Color.electricViolet
                ) {
                    showingLeadDetail = true
                }
            }
        }
    }
    
    private func notesCard(appointment: Appointment) -> some View {
        LeadFormSectionCard(title: "Notes", icon: "note.text") {
            Text(appointment.notes)
                .font(.obsidianBody)
                .foregroundColor(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
        }
    }

    private func appointmentDurationText(_ appointment: Appointment) -> String {
        let duration = appointment.endDate.timeIntervalSince(appointment.startDate)
        let safeDuration = duration.isNaN || duration < 0 ? 3600 : duration
        let hours = Int(safeDuration) / 3600
        let minutes = Int(safeDuration) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    private func loadAssociatedLead() {
        guard let appointment = appointment,
              let leadId = appointment.leadId else { return }

        let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: viewContext)
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
                        _ = await AppointmentManager.shared.updateAppointment(updated)
                    }
                }
            } else {
                print("❌ Failed to create calendar event")
            }
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
                await updateAppointment()
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
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        fetchRequest.predicate = NSPredicate(format: "id == %@", leadId as CVarArg)
        
        do {
            let leads = try context.fetch(fetchRequest)
            associatedLead = leads.first
        } catch {
            print("Failed to fetch associated lead: \(error)")
        }
    }
    
    @MainActor
    private func updateAppointment() async -> Bool {
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
        
        let success = await appointmentManager.updateAppointment(updatedAppointment)
        if success {
            dismiss()
        } else {
            print("❌ Appointment update failed")
        }
        return success
    }
}

// MARK: - Edit Form Sections

struct EditLocationSection: View {
    @Binding var location: String
    
    var body: some View {
        LeadFormSectionCard(title: "Location", icon: "location.fill") {
            VStack(alignment: .leading, spacing: 10) {
                LeadFormTextField(
                    title: "Appointment Location",
                    placeholder: "Street address or service location",
                    text: $location,
                    icon: "mappin.circle.fill"
                )

                Label("Optional: add unit number, parking notes, or service-specific details.", systemImage: "info.circle")
                    .font(.micro)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


#Preview {
    AppointmentsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
