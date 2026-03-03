import SwiftUI

struct SelectableLeadRow: View {
    let lead: Lead
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(isSelected ? Color.themePrimary : Color.themeTextSecondary.opacity(0.5), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.themePrimary : Color.clear)
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
                            .font(.themeHeadline)
                            .foregroundColor(Color.themeTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        StatusBadge(status: LeadStatus(rawValue: lead.status ?? "") ?? .new)
                    }

                    if let address = lead.address, !address.isEmpty {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(Color.themeTextSecondary)
                                .font(.caption)

                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(Color.themeTextSecondary)
                                .lineLimit(1)
                        }
                    }

                    HStack {
                        if let phone = lead.phone, !phone.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(Color.themePrimary)
                                    .font(.caption)

                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(Color.themePrimary)
                            }
                        }

                        if let email = lead.email, !email.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(Color.themeSuccess)
                                    .font(.caption)

                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(Color.themeSuccess)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let followUpDate = lead.followUpDate {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge")
                                    .foregroundColor(Color.themeWarning)
                                    .font(.caption)

                                Text(followUpDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(Color.themeWarning)
                            }
                        }
                    }
                }
            }
            .glassCard()
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.themePrimary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.themePrimary, lineWidth: 2)
                            )
                            .allowsHitTesting(false)
                    }
                }
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