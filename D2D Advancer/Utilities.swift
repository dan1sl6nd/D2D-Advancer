import Foundation
import UIKit
import CoreData

/// Utility functions and extensions for the D2D Advancer app
struct Utilities {
    
    /// Formats a phone number string to (XXX) XXX-XXXX format
    /// - Parameter phoneNumber: The raw phone number string
    /// - Returns: Formatted phone number string
    static func formatPhoneNumber(_ phoneNumber: String) -> String {
        let cleanedPhoneNumber = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        let mask = "(XXX) XXX-XXXX"

        var result = ""
        var index = cleanedPhoneNumber.startIndex
        for ch in mask where index < cleanedPhoneNumber.endIndex {
            if ch == "X" {
                result.append(cleanedPhoneNumber[index])
                index = cleanedPhoneNumber.index(after: index)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Redacts an email address for safe logging.
    /// Example: `j***@example.com`
    static func redactedEmail(_ email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = normalized.firstIndex(of: "@") else {
            return "<redacted>"
        }

        let localPart = normalized[..<atIndex]
        let domainPart = normalized[atIndex...]
        let firstCharacter = localPart.first.map(String.init) ?? ""
        return "\(firstCharacter)***\(domainPart)"
    }

    /// Redacts a free-form string for safe logging.
    static func redactedText(_ text: String, visiblePrefix: Int = 2) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<redacted>" }

        let prefixCount = max(1, min(visiblePrefix, trimmed.count))
        return "\(trimmed.prefix(prefixCount))***"
    }
    
    /// Opens a URL safely using UIApplication
    /// - Parameter urlString: The URL string to open
    static func openURL(_ urlString: String) {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else {
            print("Failed to open URL: invalid URL format")
            return
        }
        openURL(url)
    }
    
    /// Opens phone dialer with the given phone number
    /// - Parameter phoneNumber: The phone number to call
    static func makePhoneCall(to phoneNumber: String) {
        let sanitized = sanitizePhoneNumber(phoneNumber)
        guard !sanitized.isEmpty else {
            print("Empty phone number provided")
            return
        }
        openURL("tel:\(sanitized)")
    }
    
    /// Opens SMS app with the given phone number
    /// - Parameter phoneNumber: The phone number to message
    static func sendSMS(to phoneNumber: String) {
        let sanitized = sanitizePhoneNumber(phoneNumber)
        guard !sanitized.isEmpty else {
            print("Empty phone number provided")
            return
        }
        openURL("sms:\(sanitized)")
    }
    
    /// Opens email app with the given email address
    /// - Parameter email: The email address to send to
    static func sendEmail(to email: String) {
        guard let encodedEmail = sanitizedEmailAddress(email) else {
            print("Empty email address provided")
            return
        }
        openURL("mailto:\(encodedEmail)")
    }

    /// Opens Apple Maps search for a textual address/query
    static func openMapsSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode maps search query")
            return
        }
        openURL("https://maps.apple.com/?q=\(encoded)")
    }

    /// Opens Apple Maps driving directions to coordinates
    static func openMapsDirections(latitude: Double, longitude: Double) {
        guard latitude != 0 || longitude != 0 else {
            print("Invalid coordinates for navigation")
            return
        }
        openURL("https://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d")
    }
    
    /// Removes duplicate Lead entities from Core Data based on ID
    /// - Parameter context: The managed object context to operate on
    static func removeDuplicateLeads(from context: NSManagedObjectContext) {
        context.perform {
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: true)]
        
        do {
            let allLeads = try context.fetch(fetchRequest)
            var seenIDs: Set<UUID> = []
            var duplicatesToDelete: [Lead] = []
            
            for lead in allLeads {
                if let leadID = lead.id {
                    if seenIDs.contains(leadID) {
                        duplicatesToDelete.append(lead)
                        print("🗑️ Found duplicate lead: \(lead.displayName) (ID: \(leadID))")
                    } else {
                        seenIDs.insert(leadID)
                    }
                } else {
                    // Lead without ID - assign new UUID
                    lead.id = UUID()
                    print("🔧 Fixed lead without ID: \(lead.displayName)")
                }
            }
            
            // Delete duplicates
            for duplicate in duplicatesToDelete {
                context.delete(duplicate)
            }
            
            if !duplicatesToDelete.isEmpty {
                try context.save()
                print("✅ Removed \(duplicatesToDelete.count) duplicate leads from Core Data")
            } else {
                print("✅ No duplicate leads found")
            }
            
        } catch {
            print("❌ Failed to remove duplicate leads: \(error)")
        }
        }
    }

    // MARK: - Private Helpers

    private static func openURL(_ url: URL) {
        let openAction = {
            guard UIApplication.shared.canOpenURL(url) else {
                print("Cannot open URL for scheme: \(url.scheme ?? "unknown")")
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }

        if Thread.isMainThread {
            openAction()
        } else {
            DispatchQueue.main.async(execute: openAction)
        }
    }

    private static func sanitizePhoneNumber(_ phoneNumber: String) -> String {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let digits = trimmed.filter(\.isNumber)
        if trimmed.hasPrefix("+") {
            return digits.isEmpty ? "" : "+\(digits)"
        }
        return digits
    }

    private static func sanitizedEmailAddress(_ email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.contains("@") else { return nil }
        return normalized.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed)
    }
}
