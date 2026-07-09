import Foundation
import MapKit
import SwiftUI

class LeadAnnotation: NSObject, MKAnnotation {
    let lead: Lead
    
    var coordinate: CLLocationCoordinate2D {
        return lead.coordinate
    }
    
    var title: String? {
        return lead.displayName
    }
    
    var subtitle: String? {
        return lead.leadStatus.displayName
    }
    
    init(lead: Lead) {
        self.lead = lead
        super.init()
    }
}

struct LeadAnnotationView: View {
    let lead: Lead
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: pinIcon)
                .font(.obsidianCallout)
                .foregroundColor(pinColor)
                .background(
                    Circle()
                        .fill(Color.obsidianSurface)
                        .frame(width: 30, height: 30)
                )
                .overlay(
                    Circle()
                        .stroke(pinColor, lineWidth: 2)
                        .frame(width: 30, height: 30)
                )
            
            Image(systemName: "triangle.fill")
                .font(.nano)
                .foregroundColor(pinColor)
                .offset(y: -2)
        }
        .shadow(color: pinColor.opacity(0.18), radius: 5, x: 0, y: 2)
    }
    
    private var pinIcon: String {
        switch lead.leadStatus {
        case .notContacted:
            return "person.circle"
        case .interested:
            return "heart.circle"
        case .converted:
            return "checkmark.circle"
        case .notInterested:
            return "hand.raised.fill"
        case .notHome:
            return "house.slash.fill"
        }
    }
    
    private var pinColor: Color {
        lead.leadStatus.swiftUIColor
    }
}
