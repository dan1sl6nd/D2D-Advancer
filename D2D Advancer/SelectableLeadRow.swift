import SwiftUI

struct SelectableLeadRow: View {
    let lead: Lead
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.clear)
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .opacity(isSelected ? 1 : 0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lead.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        StatusBadge(status: LeadStatus(rawValue: lead.status ?? "") ?? .new)
                    }
                    
                    if let address = lead.address, !address.isEmpty {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    HStack {
                        if let phone = lead.phone, !phone.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                
                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if let email = lead.email, !email.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        if let followUpDate = lead.followUpDate {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                
                                Text(followUpDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StatusBadge: View {
    let status: LeadStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            Text(status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
        .foregroundColor(status.color)
    }
}