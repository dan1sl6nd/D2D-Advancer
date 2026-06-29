import SwiftUI

struct CustomTemplateCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared

    @State private var title: String = ""
    @State private var message: String = ""
    @State private var selectedCategory: MessageTemplate.MessageCategory = .initial
    @State private var isForSMS: Bool = true
    @State private var isForEmail: Bool = true
    @State private var showingPreview: Bool = false
    @State private var saveErrorMessage: String?
    
    let editingTemplate: MessageTemplate?
    
    init(editingTemplate: MessageTemplate? = nil) {
        self.editingTemplate = editingTemplate
        if let template = editingTemplate {
            _title = State(initialValue: template.title)
            _message = State(initialValue: template.message)
            _selectedCategory = State(initialValue: template.category)
            _isForSMS = State(initialValue: template.isForSMS)
            _isForEmail = State(initialValue: template.isForEmail)
        }
    }
    
    private var isValidTemplate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (isForSMS || isForEmail)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorHeader

                ScrollView {
                    VStack(spacing: 16) {
                        templateDetailsCard
                        messageContentCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
                .background(Color.obsidianBlack)
            }
            .background(Color.obsidianBlack)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .accessibilityIdentifier("customTemplateEditorSheet")
            .safeAreaInset(edge: .bottom) {
                ObsidianBottomActionBar(
                    isPrimaryDisabled: !isValidTemplate,
                    primaryAccessibilityIdentifier: "customTemplateSaveButton",
                    secondaryAccessibilityIdentifier: "customTemplateCancelButton",
                    primaryAction: saveTemplate,
                    secondaryAction: { dismiss() },
                    primaryLabel: {
                        Label(editingTemplate != nil ? "Update" : "Save", systemImage: "checkmark.circle.fill")
                    },
                    secondaryLabel: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                )
            }
            .sheet(isPresented: $showingPreview) {
                PreviewTemplateView(
                    title: title,
                    message: message,
                    category: selectedCategory
                )
                .presentationDetents([.large])
                .presentationBackground(Color.obsidianBlack)
            }
            .alert(
                "Template not saved",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
        }
        .presentationBackground(Color.obsidianBlack)
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(
                icon: editingTemplate != nil ? "square.and.pencil" : "plus.message.fill",
                tint: Color.electricViolet,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(editingTemplate != nil ? "Edit Template" : "Create Template")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Build a reusable reply for SMS, email, or both.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close template editor",
                accentColor: Color.textSecondary,
                accessibilityIdentifier: "customTemplateCloseButton"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(Color.obsidianBlack)
    }
    
    private func saveTemplate() {
        let template = MessageTemplate(
            id: editingTemplate?.id ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            category: selectedCategory,
            isForSMS: isForSMS,
            isForEmail: isForEmail,
            isCustom: true,
            dateCreated: editingTemplate?.dateCreated ?? Date()
        )

        let didSave: Bool
        if editingTemplate != nil {
            didSave = templateManager.updateCustomTemplate(template)
        } else {
            didSave = templateManager.addCustomTemplate(template)
        }

        guard didSave else {
            saveErrorMessage = templateManager.lastErrorMessage ?? "Could not save this template. Please try again."
            return
        }

        dismiss()
    }

    private func insertPlaceholder(_ placeholder: String) {
        // Insert placeholder at the end of the current message
        if message.isEmpty {
            message = placeholder
        } else {
            message += " \(placeholder)"
        }
    }
    
    // MARK: - Card Components
    
    private var templateDetailsCard: some View {
        ObsidianSectionCard(
            title: "Template Details",
            icon: "doc.text.fill",
            subtitle: "Name the template and choose where it appears."
        ) {
            VStack(alignment: .leading, spacing: 18) {
            LeadFormTextField(
                title: "Template Name",
                placeholder: "Enter template name",
                text: $title,
                icon: "doc.text.fill",
                accessibilityIdentifier: "customTemplateTitleField"
            )
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Category")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)
                
                Menu {
                    ForEach(MessageTemplate.MessageCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                                if selectedCategory == category {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedCategory.icon)
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 20)
                        Text(selectedCategory.rawValue)
                            .font(.obsidianBody)
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color.textSecondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
                }
                .accessibilityIdentifier("customTemplateCategoryMenu")
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Message Channels")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)

                VStack(spacing: 12) {
                    channelToggleRow(
                        title: "SMS Messages",
                        icon: "message.fill",
                        isOn: $isForSMS,
                        accessibilityIdentifier: "customTemplateSMSToggle"
                    )
                    channelToggleRow(
                        title: "Email Messages",
                        icon: "envelope.fill",
                        isOn: $isForEmail,
                        accessibilityIdentifier: "customTemplateEmailToggle"
                    )
                }
            }
        }
        }
    }

    private var messageContentCard: some View {
        ObsidianSectionCard(
            title: "Message Content",
            icon: "text.bubble.fill",
            subtitle: "Use placeholders to personalize messages from lead data."
        ) {
            VStack(alignment: .leading, spacing: 18) {
            LeadNotesEditor(
                title: "Template Message",
                text: $message,
                minHeight: 128,
                accessibilityIdentifier: "customTemplateMessageField",
                keyboardDoneAccessibilityIdentifier: "customTemplateMessageDoneButton"
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(Color.electricViolet)
                        .font(.caption)
                    Text("Insert Placeholders")
                        .font(.obsidianFootnote)
                        .foregroundColor(Color.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap to insert placeholder into your message")
                        .font(.obsidianSmall)
                        .foregroundColor(Color.textSecondary)

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Color.electricViolet)
                        Text("Use math with price: {price + 50}, {price * 1.1}, {price - 100}, {price / 2}")
                            .font(.micro)
                            .foregroundColor(Color.electricViolet)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.electricViolet.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FollowUpMessageTemplates.availablePlaceholders, id: \.placeholder) { item in
                            Button(action: {
                                insertPlaceholder(item.placeholder)
                            }) {
	                                VStack(alignment: .leading, spacing: 4) {
	                                    Text(item.placeholder)
	                                        .font(.obsidianSmall)
	                                        .foregroundColor(Color.electricViolet)
	                                    Text(item.description)
	                                        .font(.micro)
	                                        .foregroundColor(Color.textSecondary)
	                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.electricViolet.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.electricViolet.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                            .accessibilityIdentifier("customTemplatePlaceholder_\(item.placeholder)")
                        }
                    }
                }
            }
            
            if !message.isEmpty {
                Button(action: {
                    showingPreview = true
                }) {
                    HStack(spacing: 14) {
                        ObsidianIconTile(icon: "eye.fill", tint: Color.electricViolet, size: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview Message")
                                .font(.obsidianCallout)
                                .foregroundColor(Color.textPrimary)

                            Text("Check how this template looks with sample data")
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("customTemplatePreviewButton")
                .background(Color.obsidianElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                )
            }
        }
        }
    }

    private func channelToggleRow(
        title: String,
        icon: String,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: icon, tint: Color.electricViolet, size: 34)

            Text(title)
                .font(.obsidianCallout)
                .foregroundColor(Color.textPrimary)

            Spacer()

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? "Enabled" : "Disabled")
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(12)
        .background(Color.obsidianElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
        )
    }
}

struct PreviewTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let category: MessageTemplate.MessageCategory
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewHeader

                ScrollView {
                    VStack(spacing: 16) {
                        templateHeaderCard
                        messagePreviewCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .background(Color.obsidianBlack)
            }
            .background(Color.obsidianBlack)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .accessibilityIdentifier("customTemplatePreviewSheet")
        }
        .presentationBackground(Color.obsidianBlack)
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ObsidianIconTile(icon: "eye.fill", tint: Color.electricViolet, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Template Preview")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Review the final message with sample customer data.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close preview",
                accentColor: Color.textSecondary,
                accessibilityIdentifier: "customTemplatePreviewCloseButton"
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(Color.obsidianBlack)
    }

    private var templateHeaderCard: some View {
        ObsidianSectionCard(
            title: "Template Information",
            icon: "doc.text.viewfinder",
            accentColor: category == .urgent ? Color.statusNotInterested : Color.electricViolet
        ) {
            ObsidianDetailRow(
                title: category.rawValue,
                value: title,
                icon: category.icon,
                tint: category == .urgent ? Color.statusNotInterested : Color.electricViolet
            )
        }
    }

    private var messagePreviewCard: some View {
        ObsidianSectionCard(
            title: "Message Preview",
            icon: "eye.fill",
            subtitle: "Sample values are substituted before sending.",
            accentColor: Color.electricViolet
        ) {
            VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview with Sample Data")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
	                        Text("Customer: John Smith")
	                            .font(.obsidianSmall)
	                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
	                        Text("Address: 123 Main St, Toronto")
	                            .font(.obsidianSmall)
	                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
	                        Text("Price: $2,500.00 CAD")
	                            .font(.obsidianSmall)
	                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
	                        Text("Service: Window Cleaning")
	                            .font(.obsidianSmall)
	                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
	                        Text("Phone: (416) 555-1234")
	                            .font(.obsidianSmall)
	                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Email: john.smith@example.com")
                            .font(.obsidianSmall)
                            .foregroundColor(Color.textSecondary)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Personalized Message")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textPrimary)

                Text(previewMessage)
                    .font(.obsidianBody)
                    .foregroundColor(Color.textPrimary)
                    .padding(16)
                    .background(Color.obsidianElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.obsidianBorder.opacity(0.45), lineWidth: 0.5)
                    )
            }
        }
        }
    }

    private var previewMessage: String {
        var preview = message
        let samplePrice: Double = 2500.00

        // Process price expressions first
        preview = processPriceExpressions(preview, basePrice: samplePrice)

        // Then replace simple placeholders
        preview = preview.replacingOccurrences(of: "{name}", with: "John Smith")
        preview = preview.replacingOccurrences(of: "{address}", with: "123 Main St, Toronto")
        preview = preview.replacingOccurrences(of: "{price}", with: "$2,500.00 CAD")
        preview = preview.replacingOccurrences(of: "{service_type}", with: "Window Cleaning")
        preview = preview.replacingOccurrences(of: "{phone}", with: "(416) 555-1234")
        preview = preview.replacingOccurrences(of: "{email}", with: "john.smith@example.com")
        return preview
    }

    private func processPriceExpressions(_ message: String, basePrice: Double) -> String {
        var result = message

        // Find all price expressions like {price + 50}, {price * 1.1}, {price - 100}, etc.
        let pattern = "\\{price\\s*([+\\-*/])\\s*([0-9.]+)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let nsString = message as NSString
        let matches = regex.matches(in: message, options: [], range: NSRange(location: 0, length: nsString.length))

        // Process matches in reverse order to maintain correct string indices
        for match in matches.reversed() {
            guard match.numberOfRanges == 3 else { continue }

            let operatorRange = match.range(at: 1)
            let valueRange = match.range(at: 2)

            let operatorStr = nsString.substring(with: operatorRange)
            let valueStr = nsString.substring(with: valueRange)

            guard let value = Double(valueStr) else { continue }

            // Calculate the result based on the operator
            var calculatedPrice: Double = basePrice
            switch operatorStr {
            case "+":
                calculatedPrice = basePrice + value
            case "-":
                calculatedPrice = basePrice - value
            case "*":
                calculatedPrice = basePrice * value
            case "/":
                if value != 0 {
                    calculatedPrice = basePrice / value
                }
            default:
                break
            }

            // Format as currency
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "CAD"
            let priceString = formatter.string(from: NSNumber(value: calculatedPrice)) ?? "$0.00"

            // Replace the expression with the calculated value
            result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: priceString)
        }

        return result
    }
}

#Preview {
    CustomTemplateCreatorView()
}
