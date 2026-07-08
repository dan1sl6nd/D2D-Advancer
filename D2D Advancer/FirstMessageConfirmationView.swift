import SwiftUI
import MessageUI

struct FirstMessageConfirmationView: View {
    let lead: Lead
    let onCompletion: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared
    @State private var selectedTemplate: MessageTemplate?
    @State private var showingMessageComposer = false
    @State private var customMessage = ""
    @State private var showingCustomTemplateCreator = false
    @State private var templateToEdit: MessageTemplate?
    @State private var deleteErrorMessage: String?
    
    // Get initial contact templates
    private var initialTemplates: [MessageTemplate] {
        return templateManager.getTemplatesForCategory(.initial).filter { $0.isForSMS }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ObsidianScreenTitle(
                        title: "First Message",
                        subtitle: "Send an initial SMS now, or skip and do it later.",
                        icon: "message.badge.checkmark.rtl"
                    )

                    headerSection
                    leadInfoSection
                    templatesSection

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
            .accessibilityIdentifier("firstMessageConfirmationScreen")
            .obsidianScreenBackground()
            .obsidianPushedNavigation(
                "First Message",
                backButtonAccessibilityIdentifier: "firstMessageBackButton",
                onBack: {
                    dismiss()
                    onCompletion()
                }
            )
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !canSendMessage,
                    primaryAccessibilityIdentifier: "firstMessageSendButton",
                    secondaryAccessibilityIdentifier: "firstMessageSkipButton",
                    primaryAction: { showingMessageComposer = true },
                    secondaryAction: {
                        dismiss()
                        onCompletion()
                    },
                    primaryLabel: {
                        Label("Send SMS", systemImage: "message.fill")
                    },
                    secondaryLabel: {
                        Label("Skip", systemImage: "forward.fill")
                    }
                )
            }
        }
        .sheet(isPresented: $showingMessageComposer) {
            if MFMessageComposeViewController.canSendText() {
                FirstMessageComposeView(
                    recipients: [lead.phone ?? ""],
                    messageBody: getSelectedMessage(),
                    onCompletion: {
                        dismiss()
                        onCompletion()
                    }
                )
            } else {
                VStack {
                    Image(systemName: "message.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Color.textSecondary)
                    Text("SMS not available on this device")
                        .font(.obsidianHeadline)
                        .foregroundColor(Color.textSecondary)
                }
                .padding()
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
        if lead.phone?.isEmpty ?? true {
            return ("No phone number", "Add a phone number before sending an SMS.")
        }
        if customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("Message is empty", "Choose a template or write a message before sending.")
        }
        return nil
    }
    
    private var headerSection: some View {
        ObsidianStatusBanner(
            icon: "checkmark.circle.fill",
            title: "Lead saved",
            message: "Send the first message now, or skip and handle it later.",
            tint: Color.statusInterested
        )
    }
    
    private var leadInfoSection: some View {
        LeadFormSectionCard(title: "Lead Information", icon: "person.circle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 16)
                    Text(lead.displayName)
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textPrimary)
                }
                
                if let phone = lead.phone, !phone.isEmpty {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(Color.textSecondary)
                            .frame(width: 16)
                        Text(phone)
                            .font(.obsidianFootnote)
                            .foregroundColor(Color.textSecondary)
                    }
                }
                
                if let address = lead.address, !address.isEmpty {
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
            }
        }
    }
    
    private var templatesSection: some View {
        LeadFormSectionCard(title: "Choose a Template", icon: "doc.text.fill") {
            HStack {
                Spacer()
                
                ObsidianCompactIconButton(
                    icon: "plus",
                    accessibilityLabel: "Add new template",
                    accessibilityIdentifier: "firstMessageAddTemplateButton",
                    size: 36
                ) {
                    showingCustomTemplateCreator = true
                }
            }
            
            if initialTemplates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(Color.textSecondary)
                    
                    Text("No SMS templates available")
                        .font(.obsidianTitle)
                        .foregroundColor(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(initialTemplates, id: \.id) { template in
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
            
            // Custom message option
            VStack(alignment: .leading, spacing: 8) {
                Text("Or write a custom message:")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                
                TextEditor(text: $customMessage)
                    .frame(height: 80)
                    .obsidianEditorSurface(cornerRadius: 14)
                    .onChange(of: customMessage) { oldValue, newValue in
                        // Only clear template selection if user manually edited the message
                        if let currentTemplate = selectedTemplate,
                           !newValue.isEmpty && 
                           oldValue != newValue &&
                           newValue != templateManager.personalizeMessage(currentTemplate, for: lead) {
                            selectedTemplate = nil
                        }
                    }
            }
        }
    }
    
    private var canSendMessage: Bool {
        return !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !(lead.phone?.isEmpty ?? true)
    }
    
    private func getSelectedMessage() -> String {
        return customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Enhanced MessageComposeView with completion callback
struct FirstMessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let messageBody: String
    let onCompletion: (() -> Void)?
    
    init(recipients: [String], messageBody: String, onCompletion: (() -> Void)? = nil) {
        self.recipients = recipients
        self.messageBody = messageBody
        self.onCompletion = onCompletion
    }
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = messageBody
        composer.messageComposeDelegate = context.coordinator
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onCompletion: (() -> Void)?
        
        init(onCompletion: (() -> Void)?) {
            self.onCompletion = onCompletion
            super.init()
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            DispatchQueue.main.async { [weak self] in
                controller.dismiss(animated: true) {
                    switch result {
                    case .sent:
                        print("📱 First message sent successfully")
                        self?.onCompletion?()
                    case .cancelled:
                        print("📱 Message sending cancelled")
                        self?.onCompletion?()
                    case .failed:
                        print("📱 Message sending failed")
                        self?.onCompletion?()
                    @unknown default:
                        self?.onCompletion?()
                    }
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let lead = Lead.create(in: context)
    lead.name = "John Doe"
    lead.phone = "(555) 123-4567"
    lead.address = "123 Main St, Toronto, ON"
    
    return FirstMessageConfirmationView(lead: lead) {
        print("Completion called")
    }
}
