import SwiftUI

struct MessageTemplatesManagerView: View {
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared
    @State private var showingCreator = false
    @State private var editingTemplate: MessageTemplate?
    @State private var templateToDelete: MessageTemplate?
    @State private var showingDeleteConfirm = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                templateSummaryCard
                customSection
                defaultsByCategory
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(Color.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Message Templates")
        .obsidianInlineNavigation()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ObsidianCompactIconButton(
                    icon: "plus",
                    accessibilityLabel: "Create message template"
                ) {
                    editingTemplate = nil
                    showingCreator = true
                }
            }
        }
        .sheet(isPresented: $showingCreator, onDismiss: { editingTemplate = nil }) {
            CustomTemplateCreatorView(editingTemplate: editingTemplate)
        }
        .alert("Delete template?", isPresented: $showingDeleteConfirm, presenting: templateToDelete) { template in
            Button("Delete", role: .destructive) {
                withAnimation {
                    let didDelete = templateManager.deleteCustomTemplate(template)
                    if !didDelete {
                        deleteErrorMessage = templateManager.lastErrorMessage ?? "Could not delete this template. Please try again."
                    }
                }
                templateToDelete = nil
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: { template in
            Text("\"\(template.title)\" will be removed. This can't be undone.")
        }
        .alert(
            "Template not deleted",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Please try again.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var customSection: some View {
        if templateManager.customTemplates.isEmpty {
            emptyCustomCard
        } else {
            templateSection(
                title: "Your Templates",
                icon: "doc.text.fill",
                subtitle: "Reusable messages you created.",
                templates: templateManager.customTemplates,
                isCustom: true,
                accentColor: Color.electricViolet
            )
        }
    }

    private var defaultsByCategory: some View {
        ForEach(MessageTemplate.MessageCategory.allCases, id: \.self) { category in
            let inCategory = templateManager.defaultTemplates.filter { $0.category == category }
            if !inCategory.isEmpty {
                templateSection(
                    title: category.rawValue,
                    icon: category.icon,
                    subtitle: "\(inCategory.count) built-in template\(inCategory.count == 1 ? "" : "s")",
                    templates: inCategory,
                    isCustom: false,
                    accentColor: category == .urgent ? Color.statusNotInterested : Color.electricViolet
                )
            }
        }
    }

    private var templateSummaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ObsidianIconTile(icon: "text.bubble.fill", tint: Color.electricViolet, size: 48, filled: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Message Templates")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Manage reusable SMS and email replies from one clean library.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    pill(text: "\(templateManager.customTemplates.count) custom", color: Color.electricViolet)
                    pill(text: "\(templateManager.defaultTemplates.count) default", color: Color.statusInterested)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    // MARK: - Pieces

    private var emptyCustomCard: some View {
        MoreSectionGroup(
            title: "Your Templates",
            icon: "doc.text.magnifyingglass",
            subtitle: "Create your own reply once, then reuse it from lead screens.",
            accentColor: Color.electricViolet
        ) {
            Button {
                editingTemplate = nil
                showingCreator = true
            } label: {
                MoreCardView(
                    icon: "plus",
                    iconColor: Color.electricViolet,
                    title: "Create Template",
                    subtitle: "Write a reusable SMS or email reply",
                    showChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func templateSection(
        title: String,
        icon: String,
        subtitle: String,
        templates: [MessageTemplate],
        isCustom: Bool,
        accentColor: Color
    ) -> some View {
        MoreSectionGroup(
            title: title,
            icon: icon,
            subtitle: subtitle,
            accentColor: accentColor
        ) {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                templateRow(template, isCustom: isCustom)

                if index < templates.count - 1 {
                    Rectangle()
                        .fill(Color.obsidianBorder.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.leading, 68)
                }
            }
        }
    }

    private func templateRow(_ template: MessageTemplate, isCustom: Bool) -> some View {
        let previewMessage = template.message
            .replacingOccurrences(of: "{name}", with: "Alex")
            .replacingOccurrences(of: "{address}", with: "123 Main St")
            .replacingOccurrences(of: "{service_type}", with: "window cleaning")
            .replacingOccurrences(of: "{price}", with: "$150")

        return HStack(alignment: .top, spacing: 0) {
            Button {
                editingTemplate = template
                showingCreator = true
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    ObsidianIconTile(
                        icon: template.category.icon,
                        tint: template.category == .urgent ? Color.statusNotInterested : Color.electricViolet,
                        size: 42
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                                .font(.obsidianCallout)
                                .foregroundColor(Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Text(previewMessage)
                                .font(.obsidianFootnote)
                                .foregroundColor(Color.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 6) {
                            pill(text: isCustom ? "Custom" : "Default", color: isCustom ? .electricViolet : .statusInterested)

                            if template.isForSMS {
                                pill(text: "SMS", color: .textSecondary)
                            }

                            if template.isForEmail {
                                pill(text: "Email", color: .textSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.leading, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(PlainButtonStyle())

            if isCustom {
                Button {
                    templateToDelete = template
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.obsidianFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.statusNotInterested)
                        .frame(width: 38, height: 38)
                        .background(Color.statusNotInterested.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 16)
                .padding(.top, 15)
            } else {
                Image(systemName: "chevron.right")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .padding(.trailing, 16)
                    .padding(.top, 26)
            }
        }
        .contentShape(Rectangle())
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.obsidianSmall)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
