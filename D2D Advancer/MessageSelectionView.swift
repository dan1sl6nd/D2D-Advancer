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
    @State private var deleteErrorMessage: String?
    
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
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "Send Follow-up",
                        subtitle: "Choose a saved template or write a custom message.",
                        icon: messageType.icon
                    )

                    leadInfoHeader
                    messageTypeSelector
                    categorySelector
                    templatesList
                    customMessageSection

                    if let sendWarning {
                        ObsidianStatusBanner(
                            icon: "exclamationmark.triangle.fill",
                            title: sendWarning.title,
                            message: sendWarning.message,
                            tint: Color.statusNotInterested
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("messageSelectionScreen")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "Send Follow-up",
                backButtonAccessibilityIdentifier: "messageSelectionBackButton"
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !canSendMessage,
                    primaryAccessibilityIdentifier: "messageSelectionSendButton",
                    secondaryAccessibilityIdentifier: "messageSelectionCancelButton",
                    primaryAction: sendMessage,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label("Send \(messageType.rawValue)", systemImage: messageType.icon)
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
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
        .alert(
            "Template not deleted",
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

    private var sendWarning: (title: String, message: String)? {
        if messageType == .sms && (lead.phone?.isEmpty ?? true) {
            return ("No phone number", "Add a phone number to this lead before sending SMS.")
        }
        if messageType == .email && (lead.email?.isEmpty ?? true) {
            return ("No email address", "Add an email address to this lead before sending email.")
        }
        if customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("Message is empty", "Choose a template or write a message before sending.")
        }
        return nil
    }
    
    private var leadInfoHeader: some View {
        LeadFormSectionCard(title: "Customer", icon: "person.circle.fill") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(Color.textSecondary)
                                .frame(width: 16)
                            Text(lead.displayName)
                                .font(.obsidianTitle)
                                .foregroundColor(Color.textPrimary)
                        }
                        
                        if let address = lead.address {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(Color.textSecondary)
                                    .frame(width: 16)
                                Text(address)
                                    .font(.obsidianFootnote)
                                    .foregroundColor(Color.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            if let phone = lead.phone {
                                HStack {
                                    Image(systemName: "phone.fill")
                                        .foregroundColor(Color.textSecondary)
                                        .frame(width: 16)
                                    Text(phone)
                                        .font(.obsidianFootnote)
                                        .foregroundColor(Color.textSecondary)
                                }
                            }
                            
                            if let email = lead.email {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(Color.textSecondary)
                                        .frame(width: 16)
                                    Text(email)
                                        .font(.obsidianFootnote)
                                        .foregroundColor(Color.textSecondary)
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
    }
    
    private var messageTypeSelector: some View {
        LeadFormSectionCard(title: "Message Type", icon: "message.circle.fill") {
            HStack(spacing: 12) {
                ForEach(MessageType.allCases, id: \.self) { type in
                    Button(action: {
                        messageType = type
                        selectedTemplate = nil
                        customMessage = ""
                    }) {
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(messageType == type ? .white : Color.electricViolet)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(type.rawValue)
                                .font(.obsidianCallout)
                                .foregroundColor(messageType == type ? .white : Color.textPrimary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .background(messageType == type ? Color.electricViolet : Color.obsidianElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(messageType == type ? Color.electricViolet : Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var categorySelector: some View {
        LeadFormSectionCard(title: "Message Category", icon: "tag.circle.fill") {
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
    }
    
    private var templatesList: some View {
        LeadFormSectionCard(title: "Message Templates", icon: "doc.text.fill") {
            HStack {
                if !availableTemplates.isEmpty {
                    Text("\(availableTemplates.count) templates")
                        .font(.micro)
                        .foregroundColor(Color.textSecondary)
                }

                Spacer()

                ObsidianCompactIconButton(
                    icon: "plus",
                    accessibilityLabel: "Add new template",
                    accessibilityIdentifier: "messageSelectionAddTemplateButton",
                    size: 36
                ) {
                    showingCustomTemplateCreator = true
                }
            }
            
            if availableTemplates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(Color.textSecondary)
                    
                    Text("No templates available")
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textSecondary)
                    
                    Text("Switch to a different category or create a custom template.")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textSecondary)
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
                                let didDelete = templateManager.deleteCustomTemplate(template)
                                if didDelete, selectedTemplate?.id == template.id {
                                    selectedTemplate = nil
                                    customMessage = ""
                                } else if !didDelete {
                                    deleteErrorMessage = templateManager.lastErrorMessage ?? "Could not delete this template. Please try again."
                                }
                            }
                        } : nil
                    )
                }
            }
        }
    }
    
    private var customMessageSection: some View {
        LeadFormSectionCard(title: "Custom Message", icon: "pencil.circle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit or write your own message")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
                TextEditor(text: $customMessage)
                    .frame(minHeight: 100)
                    .obsidianEditorSurface(cornerRadius: 14)
                    .overlay(
                        Group {
                            if customMessage.isEmpty {
                                VStack {
                                    HStack {
                                        Text("Type your message here...")
                                            .foregroundColor(Color.textSecondary)
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
                    .font(.micro)
                Text(category.rawValue)
                    .font(.obsidianSmall)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.electricViolet : Color.obsidianElevated)
            .foregroundColor(isSelected ? .white : Color.textPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
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
                                .font(.obsidianAction)
                            Text("Edit")
                                .font(.micro)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                        .background(Color.electricViolet)
                    }
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                        onDelete?()
                    }) {
                        VStack {
                            Image(systemName: "trash")
                                .font(.obsidianAction)
                            Text("Delete")
                                .font(.micro)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                        .background(Color.statusNotInterested)
                    }
                }
                .cornerRadius(12, corners: [.topRight, .bottomRight])
            }
            
            // Main card content
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: template.category.icon)
                            .foregroundColor(template.category == .urgent ? Color.statusNotInterested : Color.electricViolet)
                            .font(.obsidianCallout)
                        
                        Text(template.title)
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                    }
                    
                    Spacer()
                    
                    if template.isCustom {
                        Text("CUSTOM")
                            .font(.micro)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.electricViolet)
                            .cornerRadius(6)
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.electricViolet)
                            .font(.obsidianCallout)
                    }
                }
                
                Text(personalizedMessage)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.electricViolet.opacity(0.14) : Color.obsidianElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.electricViolet : Color.obsidianBorder.opacity(0.45), lineWidth: isSelected ? 1.5 : 0.5)
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
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.phone = "(555) 123-4567"
    lead.email = "john@example.com"
    lead.address = "123 Main St, Toronto, ON"
    
    return MessageSelectionView(lead: lead)
}
