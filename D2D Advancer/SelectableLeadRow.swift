import SwiftUI

struct SelectableLeadRow: View {
    let lead: Lead
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(isSelected ? Color.electricViolet : Color.obsidianBorder, lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.electricViolet : Color.clear)
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
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        StatusBadge(status: LeadStatus(rawValue: lead.status ?? "") ?? .new)
                    }

                    if let address = lead.address, !address.isEmpty {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(Color.textSecondary)
                                .font(.caption)

                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    HStack {
                        if let phone = lead.phone, !phone.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(Color.electricViolet)
                                    .font(.caption)

                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(Color.electricViolet)
                            }
                        }

                        if let email = lead.email, !email.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(Color.statusInterested)
                                    .font(.caption)

                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(Color.statusInterested)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let followUpDate = lead.followUpDate {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge")
                                    .foregroundColor(Color.statusNotHome)
                                    .font(.caption)

                                Text(followUpDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(Color.statusNotHome)
                            }
                        }
                    }
                }
            }
            .surfaceCard()
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.electricViolet.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.electricViolet, lineWidth: 2)
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
    private let displayName: String
    private let color: Color

    init(status: LeadStatus) {
        self.displayName = status.displayName
        self.color = status.color
    }

    init(status: Lead.Status) {
        self.displayName = status.displayName
        self.color = status.swiftUIColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
        .foregroundColor(color)
    }
}
