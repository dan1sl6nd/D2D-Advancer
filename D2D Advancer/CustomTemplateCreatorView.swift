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
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Template Info Card
                        templateDetailsCard
                        
                        // Message Content Card
                        messageContentCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle(editingTemplate != nil ? "Edit Template" : "Create Template")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Card-based button design
                HStack(spacing: 16) {
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
                        .foregroundColor(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }

                    Button(action: {
                        saveTemplate()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text(editingTemplate != nil ? "Update Template" : "Save Template")
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
                                            !isValidTemplate ? Color.textSecondary : Color.electricViolet,
                                            !isValidTemplate ? Color.textSecondary.opacity(0.8) : Color.electricViolet.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: !isValidTemplate ? .clear : Color.electricViolet.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(!isValidTemplate)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color.obsidianBlack)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                )
            }
            .sheet(isPresented: $showingPreview) {
                PreviewTemplateView(
                    title: title,
                    message: message,
                    category: selectedCategory
                )
            }
        }
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

        if editingTemplate != nil {
            templateManager.updateCustomTemplate(template)
        } else {
            templateManager.addCustomTemplate(template)
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
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text("Template Details")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }
            
            // Template Name Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Template Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.textPrimary)

                TextField("Enter template name", text: $title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianSurface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Category Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.medium)
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
                            .foregroundColor(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color.textSecondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianSurface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            // Message Channels Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Message Channels")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.textPrimary)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 20)
                        Text("SMS Messages")
                            .font(.body)
                        Spacer()
                        Toggle("", isOn: $isForSMS)
                            .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                    }

                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 20)
                        Text("Email Messages")
                            .font(.body)
                        Spacer()
                        Toggle("", isOn: $isForEmail)
                            .toggleStyle(SwitchToggleStyle(tint: Color.electricViolet))
                    }
                }
            }
        }
        .padding(20)
        .background(Color.obsidianBlack)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var messageContentCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text("Message Content")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }
            
            // Template Message Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Template Message")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.textPrimary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color.obsidianSurface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                        )

                    if message.isEmpty {
                        Text("Type your message here...")
                            .foregroundColor(Color.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Placeholder Insertion Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(Color.electricViolet)
                        .font(.caption)
                    Text("Insert Placeholders")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap to insert placeholder into your message")
                        .font(.caption)
                        .foregroundColor(Color.textSecondary)

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Color.electricViolet)
                        Text("Use math with price: {price + 50}, {price * 1.1}, {price - 100}, {price / 2}")
                            .font(.caption2)
                            .foregroundColor(Color.electricViolet)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.electricViolet.opacity(0.05))
                    .cornerRadius(6)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FollowUpMessageTemplates.availablePlaceholders, id: \.placeholder) { item in
                            Button(action: {
                                insertPlaceholder(item.placeholder)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.placeholder)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.electricViolet)
                                    Text(item.description)
                                        .font(.caption2)
                                        .foregroundColor(Color.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.electricViolet.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.electricViolet.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
            
            // Preview Button
            if !message.isEmpty {
                Button(action: {
                    showingPreview = true
                }) {
                    HStack {
                        Image(systemName: "eye.fill")
                        Text("Preview Message")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.electricViolet)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.electricViolet.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.electricViolet.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(20)
        .background(Color.obsidianBlack)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct PreviewTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let category: MessageTemplate.MessageCategory
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        // Template Header Card
                        templateHeaderCard
                        
                        // Message Preview Card
                        messagePreviewCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Template Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var templateHeaderCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text("Template Information")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }
            
            // Template Details
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(category == .urgent ? Color.statusNotInterested : Color.electricViolet)
                        .font(.title2)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.textPrimary)

                        Text(category.rawValue)
                            .font(.subheadline)
                            .foregroundColor(Color.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(Color.obsidianBlack)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var messagePreviewCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(Color.electricViolet)
                    .font(.title2)

                Text("Message Preview")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }
            
            // Sample Data Info
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview with Sample Data")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Customer: John Smith")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Address: 123 Main St, Toronto")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Price: $2,500.00 CAD")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Service: Window Cleaning")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Phone: (416) 555-1234")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }

                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color.electricViolet)
                            .frame(width: 16)
                        Text("Email: john.smith@example.com")
                            .font(.caption)
                            .foregroundColor(Color.textSecondary)
                    }
                }
            }
            
            // Preview Message
            VStack(alignment: .leading, spacing: 12) {
                Text("Personalized Message")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.textPrimary)

                Text(previewMessage)
                    .font(.body)
                    .foregroundColor(Color.textPrimary)
                    .padding(16)
                    .background(Color.obsidianSurface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.obsidianBorder.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(Color.obsidianBlack)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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