import Foundation

struct MessageTemplate: Codable, Identifiable {
    let id: String
    let title: String
    let message: String
    let category: MessageCategory
    let isForSMS: Bool
    let isForEmail: Bool
    let isCustom: Bool
    let dateCreated: Date
    
    init(id: String = UUID().uuidString, title: String, message: String, category: MessageCategory, isForSMS: Bool, isForEmail: Bool, isCustom: Bool = false, dateCreated: Date = Date()) {
        self.id = id
        self.title = title
        self.message = message
        self.category = category
        self.isForSMS = isForSMS
        self.isForEmail = isForEmail
        self.isCustom = isCustom
        self.dateCreated = dateCreated
    }
    
    enum MessageCategory: String, CaseIterable, Codable {
        case initial = "Initial Follow-Up"
        case reminder = "Gentle Reminder"
        case urgent = "Urgent Follow-Up"
        case scheduling = "Schedule Meeting"
        case thankyou = "Thank You"
        case promotional = "Special Offer"
        case seasonal = "Seasonal"
        
        var icon: String {
            switch self {
            case .initial: return "person.wave.2"
            case .reminder: return "bell"
            case .urgent: return "exclamationmark.triangle"
            case .scheduling: return "calendar"
            case .thankyou: return "heart"
            case .promotional: return "gift"
            case .seasonal: return "leaf"
            }
        }
    }
}

class FollowUpMessageTemplates: ObservableObject {
    static let shared = FollowUpMessageTemplates()
    
    @Published var customTemplates: [MessageTemplate] = []
    private let userDefaults = UserDefaults.standard
    private let customTemplatesKey = "custom_message_templates"
    
    let defaultTemplates: [MessageTemplate] = [
        // Initial Follow-Up Messages
        MessageTemplate(
            id: "initial_friendly",
            title: "Friendly Check-in",
            message: "Hi {name}! It was great meeting you at {address}. I wanted to follow up on our conversation about our services. Do you have any questions I can help answer?",
            category: .initial,
            isForSMS: true,
            isForEmail: true,
            isCustom: false
        ),
        
        MessageTemplate(
            id: "initial_professional",
            title: "Professional Follow-up",
            message: "Hello {name}, Thank you for your time during our recent visit to {address}. I'm following up to see if you've had a chance to consider our proposal. I'm here to address any questions or concerns you might have.",
            category: .initial,
            isForSMS: false,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "initial_brief",
            title: "Quick Check-in",
            message: "Hi {name}! Just checking in after our visit to {address}. Any questions about our services? Happy to help!",
            category: .initial,
            isForSMS: true,
            isForEmail: false
        ),

        MessageTemplate(
            id: "initial_service_specific",
            title: "Service-Specific Follow-up",
            message: "Hi {name}! Thanks for considering our {service_type} services for {address}. I wanted to follow up and answer any questions you might have. We can also adjust the quote of {price} if needed. When would be a good time to discuss?",
            category: .initial,
            isForSMS: false,
            isForEmail: true
        ),

        // Gentle Reminder Messages
        MessageTemplate(
            id: "reminder_soft",
            title: "Soft Reminder",
            message: "Hi {name}, I hope you're doing well! I wanted to gently follow up on our previous conversation about services for {address}. No pressure - just wondering if you've had time to think it over?",
            category: .reminder,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "reminder_helpful",
            title: "Helpful Reminder",
            message: "Hello {name}, I understand you're probably busy, but I wanted to reach out one more time about our services for {address}. If now isn't the right time, I'd be happy to schedule a call for when it's more convenient.",
            category: .reminder,
            isForSMS: false,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "reminder_value",
            title: "Value Reminder",
            message: "Hi {name}! Just a friendly reminder about the benefits we discussed for {address}. Our services could save you time and money. Would you like to hear more about specific savings?",
            category: .reminder,
            isForSMS: true,
            isForEmail: true
        ),
        
        // Urgent Follow-Up Messages
        MessageTemplate(
            id: "urgent_deadline",
            title: "Time-Sensitive Offer",
            message: "Hi {name}, I have some time-sensitive information about services for {address}. We have a special promotion ending soon that could benefit you. Can we chat briefly today?",
            category: .urgent,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "urgent_opportunity",
            title: "Limited Opportunity",
            message: "Hello {name}, A limited opportunity has become available for {address}. I'd hate for you to miss out. Do you have 5 minutes to discuss this today?",
            category: .urgent,
            isForSMS: true,
            isForEmail: false
        ),
        
        // Scheduling Messages
        MessageTemplate(
            id: "schedule_meeting",
            title: "Schedule Meeting",
            message: "Hi {name}! I'd love to set up a brief meeting to discuss how we can help with {address}. What day works best for you this week? I'm flexible with timing.",
            category: .scheduling,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "schedule_call",
            title: "Phone Call Request",
            message: "Hello {name}, Would you be available for a quick 10-minute call to discuss your needs for {address}? I can call at your convenience. What time works best?",
            category: .scheduling,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "schedule_demo",
            title: "Request Demo",
            message: "Hi {name}! I'd like to show you exactly how our services would work for {address}. Would you be interested in a quick demo? It only takes 15 minutes and could be very valuable.",
            category: .scheduling,
            isForSMS: false,
            isForEmail: true
        ),
        
        // Thank You Messages
        MessageTemplate(
            id: "thankyou_time",
            title: "Thank You for Time",
            message: "Hi {name}, Thank you so much for taking the time to speak with me about {address}. I really appreciate your consideration and I'm here if you have any questions!",
            category: .thankyou,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "thankyou_referral",
            title: "Thank You for Referral",
            message: "Hello {name}, Thank you for referring us to your neighbor! We truly appreciate your confidence in our services. If you ever need anything for {address}, please don't hesitate to reach out.",
            category: .thankyou,
            isForSMS: true,
            isForEmail: true
        ),
        
        // Promotional Messages
        MessageTemplate(
            id: "promo_discount",
            title: "Special Discount",
            message: "Hi {name}! We're offering a special discount for {address} this month. You could save up to 20% on our services. Would you like to hear more about this limited-time offer?",
            category: .promotional,
            isForSMS: true,
            isForEmail: true
        ),

        MessageTemplate(
            id: "promo_bundle",
            title: "Bundle Offer",
            message: "Hello {name}, We have a new service bundle that would be perfect for {address}. It includes everything we discussed plus additional benefits at a great price. Interested in learning more?",
            category: .promotional,
            isForSMS: false,
            isForEmail: true
        ),

        MessageTemplate(
            id: "promo_price_quote",
            title: "Price Quote Follow-up",
            message: "Hi {name}! Following up on our {service_type} quote of {price} for {address}. This pricing is valid for the next 30 days. Would you like to move forward or discuss any adjustments?",
            category: .promotional,
            isForSMS: true,
            isForEmail: true
        ),

        MessageTemplate(
            id: "promo_deposit",
            title: "Deposit Required",
            message: "Hi {name}! To secure your {service_type} booking at {address}, we require a deposit of {price / 2} (50% of total {price}). Once received, we'll schedule your service. Ready to proceed?",
            category: .promotional,
            isForSMS: false,
            isForEmail: true
        ),

        MessageTemplate(
            id: "promo_early_bird",
            title: "Early Bird Discount",
            message: "Hi {name}! Book your {service_type} for {address} within 7 days and get our early bird rate of {price * 0.9} (10% off regular {price}). Limited spots available!",
            category: .promotional,
            isForSMS: true,
            isForEmail: true
        ),

        MessageTemplate(
            id: "promo_addon",
            title: "Add-on Service Offer",
            message: "Hello {name}, Based on your {service_type} quote of {price}, I can offer you an additional service package for only {price + 200}. This is a $500 value! Interested?",
            category: .promotional,
            isForSMS: false,
            isForEmail: true
        ),

        // Seasonal Messages
        MessageTemplate(
            id: "seasonal_spring",
            title: "Spring Preparation",
            message: "Hi {name}! Spring is the perfect time to prepare {address} for the warmer months ahead. Our spring services are now available. Would you like to schedule a consultation?",
            category: .seasonal,
            isForSMS: true,
            isForEmail: true
        ),
        
        MessageTemplate(
            id: "seasonal_winter",
            title: "Winter Preparation",
            message: "Hello {name}, Winter is approaching and it's important to prepare {address} for the colder months. Our winterization services can help protect your investment. Can we schedule a visit?",
            category: .seasonal,
            isForSMS: false,
            isForEmail: true
        )
    ]
    
    init() {
        loadCustomTemplates()
    }
    
    var allTemplates: [MessageTemplate] {
        return defaultTemplates + customTemplates
    }
    
    func addCustomTemplate(_ template: MessageTemplate) {
        var customTemplate = template
        customTemplate = MessageTemplate(
            id: template.id,
            title: template.title,
            message: template.message,
            category: template.category,
            isForSMS: template.isForSMS,
            isForEmail: template.isForEmail,
            isCustom: true,
            dateCreated: Date()
        )
        customTemplates.append(customTemplate)
        saveCustomTemplates()
    }
    
    func updateCustomTemplate(_ template: MessageTemplate) {
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = template
            saveCustomTemplates()
        }
    }
    
    func deleteCustomTemplate(_ template: MessageTemplate) {
        customTemplates.removeAll { $0.id == template.id }
        saveCustomTemplates()
    }
    
    private func saveCustomTemplates() {
        if let encoded = try? JSONEncoder().encode(customTemplates) {
            userDefaults.set(encoded, forKey: customTemplatesKey)
        }
    }
    
    private func loadCustomTemplates() {
        if let data = userDefaults.data(forKey: customTemplatesKey),
           let templates = try? JSONDecoder().decode([MessageTemplate].self, from: data) {
            customTemplates = templates
        }
    }
    
    func getTemplatesForCategory(_ category: MessageTemplate.MessageCategory) -> [MessageTemplate] {
        return allTemplates.filter { $0.category == category }
    }
    
    func getSMSTemplates() -> [MessageTemplate] {
        return allTemplates.filter { $0.isForSMS }
    }
    
    func getEmailTemplates() -> [MessageTemplate] {
        return allTemplates.filter { $0.isForEmail }
    }
    
    func personalizeMessage(_ template: MessageTemplate, for lead: Lead) -> String {
        var personalizedMessage = template.message

        // First, handle math expressions with price
        personalizedMessage = processPriceExpressions(personalizedMessage, basePrice: lead.price)

        // Replace simple placeholders with actual lead data
        personalizedMessage = personalizedMessage.replacingOccurrences(of: "{name}", with: lead.displayName)
        personalizedMessage = personalizedMessage.replacingOccurrences(of: "{address}", with: lead.address ?? "your location")

        // Format and replace simple price placeholder (if not already replaced by expression)
        if lead.price > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "CAD"
            let priceString = formatter.string(from: NSNumber(value: lead.price)) ?? "$0.00"
            personalizedMessage = personalizedMessage.replacingOccurrences(of: "{price}", with: priceString)
        } else {
            personalizedMessage = personalizedMessage.replacingOccurrences(of: "{price}", with: "$0.00")
        }

        // Replace service type placeholder
        if let serviceCategory = lead.serviceCategoryObject {
            personalizedMessage = personalizedMessage.replacingOccurrences(of: "{service_type}", with: serviceCategory.name)
        } else {
            personalizedMessage = personalizedMessage.replacingOccurrences(of: "{service_type}", with: "our services")
        }

        // Replace phone placeholder
        personalizedMessage = personalizedMessage.replacingOccurrences(of: "{phone}", with: lead.phone ?? "your phone number")

        // Replace email placeholder
        personalizedMessage = personalizedMessage.replacingOccurrences(of: "{email}", with: lead.email ?? "your email")

        return personalizedMessage
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

    // Available placeholders for templates
    static let availablePlaceholders: [(placeholder: String, description: String)] = [
        ("{name}", "Customer name"),
        ("{address}", "Customer address"),
        ("{price}", "Deal price"),
        ("{price + 50}", "Price plus 50"),
        ("{price - 100}", "Price minus 100"),
        ("{price * 1.1}", "Price times 1.1"),
        ("{price / 2}", "Price divided by 2"),
        ("{service_type}", "Service category"),
        ("{phone}", "Phone number"),
        ("{email}", "Email address")
    ]
}