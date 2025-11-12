import SwiftUI
import MessageUI

struct MessageSelectionView: View {
    let lead: Lead
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared
    @State private var selectedTemplate: MessageTemplate?
    @State private var customMessage = ""
    @State private var showingMessageComposer = false
    @State private var showingEmailComposer = false
    @State private var messageType: MessageType = .sms
    @State private var selectedCategory: MessageTemplate.MessageCategory = .initial
    @State private var showingCustomTemplateCreator = false
    @State private var showingTemplateOptions = false
    @State private var templateToEdit: MessageTemplate?
    
    enum MessageType: String, CaseIterable {
        case sms = "SMS"
        case email = "Email"
        
        var icon: String {
            switch self {
            case .sms: return "message.fill"
            case .email: return "envelope.fill"
            }
        }
    }
    
    private var availableTemplates: [MessageTemplate] {
        let templates = templateManager.getTemplatesForCategory(selectedCategory)
        return templates.filter { messageType == .sms ? $0.isForSMS : $0.isForEmail }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Lead Info Header Card
                        leadInfoHeader
                        
                        // Message Type Selector Card
                        messageTypeSelector
                        
                        // Category Selector Card
                        categorySelector
                        
                        // Templates List Card
                        templatesList
                        
                        // Custom Message Section Card
                        customMessageSection
                        
                        // Send Button
                        sendButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Send Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based cancel button design
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
        .sheet(isPresented: $showingMessageComposer) {
            if MFMessageComposeViewController.canSendText() {
                MessageComposeView(
                    recipients: [lead.phone ?? ""],
                    messageBody: getMessageText()
                )
            } else {
                Text("SMS not available on this device")
            }
        }
        .sheet(isPresented: $showingEmailComposer) {
            if MFMailComposeViewController.canSendMail() {
                EmailComposeView(
                    recipients: [lead.email ?? ""],
                    subject: "Follow-up: \(lead.displayName)",
                    messageBody: getMessageText()
                )
            } else {
                Text("Email not configured on this device")
            }
        }
        .sheet(isPresented: $showingCustomTemplateCreator) {
            CustomTemplateCreatorView(editingTemplate: templateToEdit)
        }
        .onDisappear {
            templateToEdit = nil
        }
    }
    
    private var leadInfoHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Customer Information")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(lead.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        
                        if let address = lead.address {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                Text(address)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            if let phone = lead.phone {
                                HStack {
                                    Image(systemName: "phone.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)
                                    Text(phone)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let email = lead.email {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    StatusBadge(status: LeadStatus.from(leadStatus: lead.leadStatus))
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var messageTypeSelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "message.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Message Type")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                ForEach(MessageType.allCases, id: \.self) { type in
                    Button(action: {
                        messageType = type
                        selectedTemplate = nil
                        customMessage = ""
                    }) {
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(messageType == type ? .white : .blue)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(type.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(messageType == type ? .white : .primary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(messageType == type ? Color.blue : Color(UIColor.tertiarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(messageType == type ? Color.blue : Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "tag.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Message Category")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MessageTemplate.MessageCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                            selectedTemplate = nil
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var templatesList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Message Templates")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !availableTemplates.isEmpty {
                    Text("\(availableTemplates.count) templates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    showingCustomTemplateCreator = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add new template")
            }
            
            if availableTemplates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No templates available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Switch to a different category or create a custom template.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(availableTemplates, id: \.id) { template in
                    TemplateCardView(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id,
                        personalizedMessage: templateManager.personalizeMessage(template, for: lead),
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTemplate = template
                                customMessage = templateManager.personalizeMessage(template, for: lead)
                            }
                        },
                        onEdit: template.isCustom ? {
                            templateToEdit = template
                            showingCustomTemplateCreator = true
                        } : nil,
                        onDelete: template.isCustom ? {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                templateManager.deleteCustomTemplate(template)
                                if selectedTemplate?.id == template.id {
                                    selectedTemplate = nil
                                    customMessage = ""
                                }
                            }
                        } : nil
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var customMessageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Custom Message")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit or write your own message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customMessage)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if customMessage.isEmpty {
                                VStack {
                                    HStack {
                                        Text("Type your message here...")
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 20)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var sendButton: some View {
        VStack(spacing: 16) {
            if messageType == .sms && (lead.phone?.isEmpty ?? true) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("No phone number available for SMS")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else if messageType == .email && (lead.email?.isEmpty ?? true) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("No email address available")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(action: sendMessage) {
                HStack(spacing: 12) {
                    Image(systemName: messageType.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text("Send \(messageType.rawValue)")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSendMessage ? Color.blue : Color.gray)
                        .shadow(color: canSendMessage ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                )
                .foregroundColor(.white)
            }
            .disabled(!canSendMessage)
        }
    }
    
    private var canSendMessage: Bool {
        !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ((messageType == .sms && !(lead.phone?.isEmpty ?? true)) ||
         (messageType == .email && !(lead.email?.isEmpty ?? true)))
    }
    
    private func getMessageText() -> String {
        return customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func sendMessage() {
        if messageType == .sms {
            showingMessageComposer = true
        } else {
            showingEmailComposer = true
        }
    }
}

struct CategoryButton: View {
    let category: MessageTemplate.MessageCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(UIColor.tertiarySystemBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

struct TemplateCardView: View {
    let template: MessageTemplate
    let isSelected: Bool
    let personalizedMessage: String
    let action: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @State private var offset: CGFloat = 0
    @State private var showingActions = false
    
    init(template: MessageTemplate, isSelected: Bool, personalizedMessage: String, action: @escaping () -> Void, onEdit: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.template = template
        self.isSelected = isSelected
        self.personalizedMessage = personalizedMessage
        self.action = action
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Background action buttons (shown when swiped)
            if template.isCustom && offset < -10 {
                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                        onEdit?()
                    }) {
                        VStack {
                            Image(systemName: "pencil")
                                .font(.title2)
                            Text("Edit")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                        .background(Color.blue)
                    }
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                        onDelete?()
                    }) {
                        VStack {
                            Image(systemName: "trash")
                                .font(.title2)
                            Text("Delete")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                    }
                }
                .cornerRadius(12, corners: [.topRight, .bottomRight])
            }
            
            // Main card content
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: template.category.icon)
                            .foregroundColor(template.category == .urgent ? .red : .blue)
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(template.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    if template.isCustom {
                        Text("CUSTOM")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple)
                            .cornerRadius(6)
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                
                Text(personalizedMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(UIColor.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .offset(x: offset, y: 0)
            .onTapGesture {
                action()
            }
        }
        .contentShape(Rectangle())
        .gesture(
            template.isCustom ? 
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    let translation = value.translation.width
                    if translation < 0 {
                        offset = max(translation, -160)
                    } else if offset < 0 {
                        offset = min(translation + offset, 0)
                    }
                }
                .onEnded { value in
                    withAnimation(.spring()) {
                        if value.translation.width < -50 {
                            offset = -160
                        } else {
                            offset = 0
                        }
                    }
                }
            : nil
        )
        .clipped()
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Keep the old TemplateRowView for compatibility if needed elsewhere
struct TemplateRowView: View {
    let template: MessageTemplate
    let isSelected: Bool
    let personalizedMessage: String
    let action: () -> Void
    
    var body: some View {
        TemplateCardView(
            template: template,
            isSelected: isSelected,
            personalizedMessage: personalizedMessage,
            action: action
        )
    }
}

// Placeholder views for message composers
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let messageBody: String
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = messageBody
        composer.messageComposeDelegate = context.coordinator
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true)
            }
        }
    }
}

struct EmailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let messageBody: String
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.setToRecipients(recipients)
        composer.setSubject(subject)
        composer.setMessageBody(messageBody, isHTML: false)
        composer.mailComposeDelegate = context.coordinator
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true)
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead(context: context)
    lead.name = "John Doe"
    lead.phone = "(555) 123-4567"
    lead.email = "john@example.com"
    lead.address = "123 Main St, Toronto, ON"
    
    return MessageSelectionView(lead: lead)
}
