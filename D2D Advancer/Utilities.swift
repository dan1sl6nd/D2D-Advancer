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
    
    /// Opens a URL safely using UIApplication
    /// - Parameter urlString: The URL string to open
    static func openURL(_ urlString: String) {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              UIApplication.shared.canOpenURL(url) else {
            print("Failed to open URL: \(urlString)")
            return
        }
        UIApplication.shared.open(url)
    }
    
    /// Opens phone dialer with the given phone number
    /// - Parameter phoneNumber: The phone number to call
    static func makePhoneCall(to phoneNumber: String) {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty phone number provided")
            return
        }
        openURL("tel:\(phoneNumber)")
    }
    
    /// Opens SMS app with the given phone number
    /// - Parameter phoneNumber: The phone number to message
    static func sendSMS(to phoneNumber: String) {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty phone number provided")
            return
        }
        openURL("sms:\(phoneNumber)")
    }
    
    /// Opens email app with the given email address
    /// - Parameter email: The email address to send to
    static func sendEmail(to email: String) {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty email address provided")
            return
        }
        openURL("mailto:\(email)")
    }
    
    /// Removes duplicate Lead entities from Core Data based on ID
    /// - Parameter context: The managed object context to operate on
    static func removeDuplicateLeads(from context: NSManagedObjectContext) {
        context.perform {
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
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
}
