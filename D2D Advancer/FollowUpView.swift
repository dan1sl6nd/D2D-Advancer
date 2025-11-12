import SwiftUI
import CoreData
import UserNotifications

struct FollowUpView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedLead: Lead?
    @State private var leadForMessaging: Lead?
    @State private var leadForCheckIn: Lead?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Lead.followUpDate, ascending: true)],
        predicate: NSPredicate(format: "followUpDate != nil"),
        animation: .default
    )
    private var followUpLeads: FetchedResults<Lead>
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Dynamic safe area spacer that adapts to device
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
                    
                    if followUpLeads.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(followUpLeads, id: \.id) { lead in
                                    FollowUpInteractiveRowView(
                                        lead: lead,
                                        onTap: {
                                            selectedLead = lead
                                        },
                                        onMessageTap: {
                                            leadForMessaging = lead
                                        },
                                        onCheckInTap: {
                                            leadForCheckIn = lead
                                        },
                                        onDelete: {
                                            // Remove follow-up date instead of deleting lead
                                            lead.setFollowUpDate(nil)
                                            UserDataSyncManager.shared.syncWithServer()
                                        }
                                    )
                                    .onLongPressGesture {
                                        // Haptic feedback
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.impactOccurred()
                                        
                                        // Show delete confirmation
                                        let alert = UIAlertController(
                                            title: "Remove Follow-up",
                                            message: "Remove follow-up reminder for \(lead.displayName)?",
                                            preferredStyle: .alert
                                        )
                                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
                                            lead.setFollowUpDate(nil)
                                            UserDataSyncManager.shared.syncWithServer()
                                        })
                                        
                                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                           let window = windowScene.windows.first {
                                            window.rootViewController?.present(alert, animated: true)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
            .sheet(item: $selectedLead) { lead in
                FollowUpDetailView(lead: lead)
            }
            .sheet(item: $leadForMessaging) { lead in
                MessageSelectionView(lead: lead)
            }
            .sheet(item: $leadForCheckIn) { lead in
                AddCheckInView(lead: lead)
            }
        }
    }
    
    private func deleteLeads(offsets: IndexSet) {
        withAnimation {
            offsets.map { followUpLeads[$0] }.forEach { lead in
                // Instead of deleting the lead, just remove the follow-up date
                lead.setFollowUpDate(nil)
            }

            // Note: Context save is handled by setFollowUpDate()

            // Trigger immediate sync for follow-up deletions
            print("🔄 Follow-ups deleted, triggering immediate sync...")
            UserDataSyncManager.shared.syncWithServer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                )
            
            VStack(spacing: 8) {
                Text("No Follow Ups Scheduled")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("When you set follow-up dates for leads, they'll appear here sorted by date.")
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
    
}

struct FeatureBullet: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

struct FollowUpInteractiveRowView: View {
    @ObservedObject var lead: Lead
    let onTap: () -> Void
    let onMessageTap: () -> Void
    let onCheckInTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Lead initial circle
            Circle()
                .fill(leadInitialColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(leadInitial)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lead.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    if let followUpDate = lead.followUpDate {
                        HStack(spacing: 4) {
                            Image(systemName: timeIcon(for: followUpDate))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(timeColor(for: followUpDate))
                                .accessibilityHidden(true)
                            Text(timeStatus(for: followUpDate))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundColor(timeColor(for: followUpDate))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(timeColor(for: followUpDate).opacity(0.15))
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Follow-up status")
                        .accessibilityValue(timeStatus(for: followUpDate))
                    }
                }
                
                if let address = lead.address, !address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text(address)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Address")
                    .accessibilityValue(address)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        onMessageTap()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                            Text("Message")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(hasContactInfo ? Color.blue : Color.gray)
                        .cornerRadius(16)
                    }
                    .disabled(!hasContactInfo)
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        onCheckInTap()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                            Text("Check-in")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.top, 8)
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
            
            Button {
                onMessageTap()
            } label: {
                Label("Send Message", systemImage: "message")
            }
            .disabled(!hasContactInfo)
            
            Button {
                onCheckInTap()
            } label: {
                Label("Record Check-in", systemImage: "checkmark.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove Follow-up", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    private var hasContactInfo: Bool {
        !(lead.phone?.isEmpty ?? true) || !(lead.email?.isEmpty ?? true)
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }
    
    private var leadInitialColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        let hash = lead.displayName.hash
        return colors[abs(hash) % colors.count]
    }
    
    private func timeIcon(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "exclamationmark.triangle.fill"
        } else if Calendar.current.isDateInToday(date) {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }
    
    private func timeColor(for date: Date) -> Color {
        let now = Date()
        if date < now {
            return .red
        } else if Calendar.current.isDateInToday(date) {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func timeStatus(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "Overdue"
        } else if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
            return "In \(days) days"
        }
    }
}

struct FollowUpRowView: View {
    @ObservedObject var lead: Lead
    let onMessageTap: () -> Void
    let onCheckInTap: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Lead initial circle
            Circle()
                .fill(leadInitialColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(leadInitial)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lead.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Spacer()
                    
                    if let followUpDate = lead.followUpDate {
                        HStack(spacing: 4) {
                            Image(systemName: timeIcon(for: followUpDate))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(timeColor(for: followUpDate))
                                .accessibilityHidden(true)
                            Text(timeStatus(for: followUpDate))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .foregroundColor(timeColor(for: followUpDate))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(timeColor(for: followUpDate).opacity(0.15))
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Follow-up status")
                        .accessibilityValue(timeStatus(for: followUpDate))
                    }
                }
                
                if let address = lead.address, !address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text(address)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Address")
                    .accessibilityValue(address)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        onMessageTap()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                            Text("Message")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(hasContactInfo ? Color.blue : Color.gray)
                        .cornerRadius(16)
                    }
                    .disabled(!hasContactInfo)
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        onCheckInTap()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                            Text("Check-in")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.top, 8)
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
    }
    
    private var hasContactInfo: Bool {
        !(lead.phone?.isEmpty ?? true) || !(lead.email?.isEmpty ?? true)
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }
    
    private var leadInitialColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        let hash = lead.displayName.hash
        return colors[abs(hash) % colors.count]
    }
    
    private func timeIcon(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "exclamationmark.triangle.fill"
        } else if Calendar.current.isDateInToday(date) {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }
    
    private func timeColor(for date: Date) -> Color {
        let now = Date()
        if date < now {
            return .red
        } else if Calendar.current.isDateInToday(date) {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func timeStatus(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "Overdue"
        } else if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
            return "In \(days) days"
        }
    }
}

struct FollowUpDetailView: View {
    @ObservedObject var lead: Lead
    @Environment(\.dismiss) private var dismiss
    @State private var leadForMessaging: Lead?
    @State private var leadForCheckIn: Lead?
    @State private var showingLeadDetail = false
    @State private var showingRescheduleView = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Circle()
                                .fill(leadInitialColor)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(leadInitial)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lead.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                if let address = lead.address, !address.isEmpty {
                                    Text(address)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(20)
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
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                    )
                    
                    // Follow-Up Information Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.orange)
                                .font(.title2)
                            
                            Text("Follow-Up Details")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        if let followUpDate = lead.followUpDate {
                            VStack(alignment: .leading, spacing: 12) {
                                // Status Badge
                                HStack {
                                    Text("Status:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: timeIcon(for: followUpDate))
                                            .foregroundColor(timeColor(for: followUpDate))
                                        Text(timeStatus(for: followUpDate))
                                            .fontWeight(.medium)
                                            .foregroundColor(timeColor(for: followUpDate))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(timeColor(for: followUpDate).opacity(0.15))
                                    )
                                    
                                    Spacer()
                                }
                                
                                // Scheduled Date & Time
                                HStack {
                                    Text("Scheduled:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(followUpDate.formatted(.dateTime.day().month().year().weekday(.wide)))
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text(followUpDate.formatted(.dateTime.hour().minute()))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                        }
                        
                        // Lead Notes
                        if let notes = lead.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(notes)
                                    .font(.body)
                                    .padding(12)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(20)
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
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                    )
                    
                    // Quick Actions Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            
                            Text("Quick Actions")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            // Message Button
                            Button(action: {
                                leadForMessaging = lead
                            }) {
                                HStack {
                                    Image(systemName: "message.fill")
                                        .foregroundColor(.white)
                                    Text("Send Message")
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(hasContactInfo ? Color.blue : Color.gray)
                                .cornerRadius(12)
                            }
                            .disabled(!hasContactInfo)
                            
                            // Check-in Button
                            Button(action: {
                                leadForCheckIn = lead
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                    Text("Record Check-in")
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                            
                            // Reschedule Button
                            if lead.followUpDate != nil {
                                Button(action: {
                                    showingRescheduleView = true
                                }) {
                                    HStack {
                                        Image(systemName: "calendar.badge.plus")
                                            .foregroundColor(.white)
                                        Text("Reschedule Follow-up")
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                                }
                            }
                            
                            // View Full Lead Details Button
                            Button(action: {
                                showingLeadDetail = true
                            }) {
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.primary)
                                    Text("View Full Lead Details")
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(20)
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
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Follow-Up")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                HStack(spacing: 16) {
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
                    
                    Menu {
                        Button("View Lead Details") {
                            showingLeadDetail = true
                        }
                        
                        if lead.followUpDate != nil {
                            Button("Reschedule") {
                                showingRescheduleView = true
                            }
                            
                            Button("Complete Follow-up") {
                                completeFollowUp()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title3)
                            Text("Options")
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(item: $leadForMessaging) { lead in
                MessageSelectionView(lead: lead)
            }
            .sheet(item: $leadForCheckIn) { lead in
                AddCheckInView(lead: lead)
            }
            .sheet(isPresented: $showingLeadDetail) {
                LeadDetailView(lead: lead)
            }
            .sheet(isPresented: $showingRescheduleView) {
                RescheduleFollowUpView(lead: lead, currentDate: lead.followUpDate ?? Date())
            }
        }
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }
    
    private var leadInitialColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        let hash = lead.displayName.hash
        return colors[abs(hash) % colors.count]
    }
    
    private var hasContactInfo: Bool {
        !(lead.phone?.isEmpty ?? true) || !(lead.email?.isEmpty ?? true)
    }
    
    private func timeIcon(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "exclamationmark.triangle.fill"
        } else if Calendar.current.isDateInToday(date) {
            return "clock.fill"
        } else {
            return "calendar"
        }
    }
    
    private func timeColor(for date: Date) -> Color {
        let now = Date()
        if date < now {
            return .red
        } else if Calendar.current.isDateInToday(date) {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func timeStatus(for date: Date) -> String {
        let now = Date()
        if date < now {
            return "Overdue"
        } else if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
            return "In \(days) days"
        }
    }
    
    private func completeFollowUp() {
        lead.setFollowUpDate(nil)
        dismiss()
    }
}

struct RescheduleFollowUpView: View {
    @ObservedObject var lead: Lead
    let currentDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date
    
    init(lead: Lead, currentDate: Date) {
        self.lead = lead
        self.currentDate = currentDate
        self._newDate = State(initialValue: currentDate)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Circle()
                                .fill(leadInitialColor)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(leadInitial)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lead.displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Reschedule Follow-up")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        // Current vs New Date Comparison
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    
                                    Text(currentDate.formatted(.dateTime.day().month().year().hour().minute()))
                                        .font(.body)
                                        .foregroundColor(.red)
                                        .strikethrough()
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("New")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    
                                    Text(newDate.formatted(.dateTime.day().month().year().hour().minute()))
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.tertiarySystemBackground))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Date Selection Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                                .font(.title2)
                            
                            Text("Select New Date & Time")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        // Modern Date Picker
                        DatePicker("Follow-up Date", selection: $newDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .padding(.vertical, 8)
                        
                        // Quick Time Suggestions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Suggestions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ], spacing: 8) {
                                QuickTimeButton(title: "Tomorrow 9 AM", date: Calendar.current.date(byAdding: .day, value: 1, to: Date())?.setting(hour: 9, minute: 0) ?? Date(), selectedDate: $newDate)
                                
                                QuickTimeButton(title: "Tomorrow 2 PM", date: Calendar.current.date(byAdding: .day, value: 1, to: Date())?.setting(hour: 14, minute: 0) ?? Date(), selectedDate: $newDate)
                                
                                QuickTimeButton(title: "In 3 Days 10 AM", date: Calendar.current.date(byAdding: .day, value: 3, to: Date())?.setting(hour: 10, minute: 0) ?? Date(), selectedDate: $newDate)
                                
                                QuickTimeButton(title: "Next Week 9 AM", date: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())?.setting(hour: 9, minute: 0) ?? Date(), selectedDate: $newDate)
                            }
                        }
                    }
                    .padding(20)
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
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                    )
                    .padding(.horizontal, 16)
                    
                    // Summary Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            
                            Text("Summary")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Lead:")
                                    .foregroundColor(.secondary)
                                Text(lead.displayName)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            HStack {
                                Text("New Follow-up:")
                                    .foregroundColor(.secondary)
                                Text(newDate.formatted(.dateTime.day().month().year().weekday(.abbreviated).hour().minute()))
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            
                            if let timeUntil = timeUntilFollowUp {
                                HStack {
                                    Text("Time until:")
                                        .foregroundColor(.secondary)
                                    Text(timeUntil)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(20)
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
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                    )
                    .padding(.horizontal, 16)
                    
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 80, height: 36)
                    .background(Color.gray)
                    .cornerRadius(20)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        lead.setFollowUpDate(newDate)
                        dismiss()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 70, height: 36)
                    .background(newDate <= Date() ? Color.gray.opacity(0.6) : Color.blue)
                    .cornerRadius(20)
                    .disabled(newDate <= Date())
                }
            }
        }
    }
    
    private var leadInitial: String {
        String(lead.displayName.prefix(1)).uppercased()
    }
    
    private var leadInitialColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        let hash = lead.displayName.hash
        return colors[abs(hash) % colors.count]
    }
    
    private var timeUntilFollowUp: String? {
        let timeInterval = newDate.timeIntervalSince(Date())
        if timeInterval <= 0 { return nil }
        
        let days = Int(timeInterval / 86400)
        let hours = Int((timeInterval.truncatingRemainder(dividingBy: 86400)) / 3600)
        
        if days > 0 {
            return days == 1 ? "1 day" : "\(days) days"
        } else if hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        } else {
            let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
    }
}

struct QuickTimeButton: View {
    let title: String
    let date: Date
    @Binding var selectedDate: Date
    
    var body: some View {
        Button(action: {
            selectedDate = date
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

extension Date {
    func setting(hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: self)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    
    // Create sample leads with follow-up dates
    let lead1 = Lead(context: context)
    lead1.name = "John Doe"
    lead1.followUpDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
    lead1.address = "123 Main St, Toronto, ON"
    lead1.notes = "Very interested in our service"
    
    let lead2 = Lead(context: context)
    lead2.name = "Jane Smith"
    lead2.followUpDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
    lead2.address = "456 Oak Ave, Toronto, ON"
    
    return FollowUpView()
        .environment(\.managedObjectContext, context)
}

