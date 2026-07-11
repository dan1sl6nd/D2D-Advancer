import Foundation
import UIKit
import CoreData

#if !DEBUG
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // Keep app-owned diagnostic output out of distribution builds.
}
#endif

enum AppLog {
    static func debug(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("🔎 [\(category)] \(message())")
        #endif
    }

    static func info(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("ℹ️ [\(category)] \(message())")
        #endif
    }

    static func warning(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("⚠️ [\(category)] \(message())")
        #endif
    }

    static func error(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("❌ [\(category)] \(message())")
        #endif
    }
}

enum AppVersionDisplay {
    static var current: String {
        formatted(
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func formatted(shortVersion: String?, build: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = build?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (version?.isEmpty == false ? version : nil, buildNumber?.isEmpty == false ? buildNumber : nil) {
        case let (.some(version), .some(buildNumber)):
            return "\(version) (\(buildNumber))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(buildNumber)):
            return "Build \(buildNumber)"
        case (.none, .none):
            return "Unknown"
        }
    }
}

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
            AppLog.warning("Utilities", "Failed to open URL: invalid URL format")
            return
        }
        openURL(url)
    }
    
    /// Opens phone dialer with the given phone number
    /// - Parameter phoneNumber: The phone number to call
    static func makePhoneCall(to phoneNumber: String) {
        let sanitized = sanitizePhoneNumber(phoneNumber)
        guard !sanitized.isEmpty else {
            AppLog.warning("Utilities", "Empty phone number provided")
            return
        }
        openURL("tel:\(sanitized)")
    }
    
    /// Opens SMS app with the given phone number
    /// - Parameter phoneNumber: The phone number to message
    static func sendSMS(to phoneNumber: String) {
        let sanitized = sanitizePhoneNumber(phoneNumber)
        guard !sanitized.isEmpty else {
            AppLog.warning("Utilities", "Empty phone number provided")
            return
        }
        openURL("sms:\(sanitized)")
    }
    
    /// Opens email app with the given email address
    /// - Parameter email: The email address to send to
    static func sendEmail(to email: String) {
        guard let encodedEmail = sanitizedEmailAddress(email) else {
            AppLog.warning("Utilities", "Empty email address provided")
            return
        }
        openURL("mailto:\(encodedEmail)")
    }

    /// Opens Apple Maps search for a textual address/query
    static func openMapsSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            AppLog.warning("Utilities", "Failed to encode maps search query")
            return
        }
        openURL("https://maps.apple.com/?q=\(encoded)")
    }

    /// Opens Apple Maps driving directions to coordinates
    static func openMapsDirections(latitude: Double, longitude: Double) {
        guard latitude != 0 || longitude != 0 else {
            AppLog.warning("Utilities", "Invalid coordinates for navigation")
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
                        AppLog.debug("Utilities", "Found duplicate lead: \(Utilities.redactedText(lead.displayName)) (ID: \(leadID))")
                    } else {
                        seenIDs.insert(leadID)
                    }
                } else {
                    // Lead without ID - assign new UUID
                    lead.id = UUID()
                    AppLog.debug("Utilities", "Fixed lead without ID: \(Utilities.redactedText(lead.displayName))")
                }
            }
            
            // Delete duplicates
            for duplicate in duplicatesToDelete {
                context.delete(duplicate)
            }
            
            if !duplicatesToDelete.isEmpty {
                try context.save()
                AppLog.info("Utilities", "Removed \(duplicatesToDelete.count) duplicate leads from Core Data")
            } else {
                AppLog.debug("Utilities", "No duplicate leads found")
            }
            
        } catch {
            AppLog.error("Utilities", "Failed to remove duplicate leads: \(error.localizedDescription)")
        }
        }
    }

    // MARK: - Private Helpers

    private static func openURL(_ url: URL) {
        let openAction = {
            guard UIApplication.shared.canOpenURL(url) else {
                AppLog.warning("Utilities", "Cannot open URL for scheme: \(url.scheme ?? "unknown")")
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
