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
                .font(.title2)
                .foregroundColor(pinColor)
                .background(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                )
                .overlay(
                    Circle()
                        .stroke(pinColor, lineWidth: 2)
                        .frame(width: 30, height: 30)
                )
            
            Image(systemName: "triangle.fill")
                .font(.caption)
                .foregroundColor(pinColor)
                .offset(y: -2)
        }
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
        switch lead.leadStatus {
        case .notContacted:
            return .gray
        case .interested:
            return .orange
        case .converted:
            return .green
        case .notInterested:
            return .red
        case .notHome:
            return .brown
        }
    }
}