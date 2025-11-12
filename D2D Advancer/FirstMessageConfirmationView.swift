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
    
    // Get initial contact templates
    private var initialTemplates: [MessageTemplate] {
        return templateManager.getTemplatesForCategory(.initial).filter { $0.isForSMS }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Lead info
                    leadInfoSection
                    
                    // Message templates
                    templatesSection
                    
                    // Action buttons
                    actionButtonsSection
                }
                .padding()
            }
            .navigationTitle("Send First Message")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground))
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
                        .foregroundColor(.secondary)
                    Text("SMS not available on this device")
                        .font(.headline)
                        .foregroundColor(.secondary)
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
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "message.badge.checkmark.rtl")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Great! Your lead has been saved.")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text("Would you like to send your first message now?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
    
    private var leadInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Lead Information")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(lead.displayName)
                        .font(.headline)
                }
                
                if let phone = lead.phone, !phone.isEmpty {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text(phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let address = lead.address, !address.isEmpty {
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
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
    
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Choose a Template")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    showingCustomTemplateCreator = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add new template")
            }
            
            if initialTemplates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("No SMS templates available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(initialTemplates, id: \.id) { template in
                    EnhancedTemplateCard(
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
            
            // Custom message option
            VStack(alignment: .leading, spacing: 8) {
                Text("Or write a custom message:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customMessage)
                    .frame(height: 80)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: customMessage) { oldValue, newValue in
                        // Only clear template selection if user manually edited the message
                        if selectedTemplate != nil && 
                           !newValue.isEmpty && 
                           oldValue != newValue &&
                           newValue != templateManager.personalizeMessage(selectedTemplate!, for: lead) {
                            selectedTemplate = nil
                        }
                    }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Send Message Button
            Button(action: {
                showingMessageComposer = true
            }) {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Send Message")
                        .font(.system(size: 16, weight: .semibold))
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
            
            // Skip Button
            Button(action: {
                dismiss()
                onCompletion()
            }) {
                Text("Skip for now")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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

struct TemplateCard: View {
    let template: MessageTemplate
    let isSelected: Bool
    let personalizedMessage: String
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color(UIColor.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
        )
        .onTapGesture {
            action()
        }
    }
}

struct EnhancedTemplateCard: View {
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
                .cornerRadius(8, corners: [.topRight, .bottomRight])
            }
            
            // Main card content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: template.category.icon)
                            .foregroundColor(template.category == .urgent ? .red : .blue)
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(template.title)
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    if template.isCustom {
                        Text("CUSTOM")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple)
                            .cornerRadius(4)
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(UIColor.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
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
    let lead = Lead(context: context)
    lead.name = "John Doe"
    lead.phone = "(555) 123-4567"
    lead.address = "123 Main St, Toronto, ON"
    
    return FirstMessageConfirmationView(lead: lead) {
        print("Completion called")
    }
}