import SwiftUI

struct MessageTemplatesManagerView: View {
    @ObservedObject private var templateManager = FollowUpMessageTemplates.shared
    @State private var showingCreator = false
    @State private var editingTemplate: MessageTemplate?
    @State private var templateToDelete: MessageTemplate?
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                customSection
                defaultsByCategory
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(Color.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Message Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingTemplate = nil
                    showingCreator = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.electricViolet)
                }
            }
        }
        .sheet(isPresented: $showingCreator, onDismiss: { editingTemplate = nil }) {
            CustomTemplateCreatorView(editingTemplate: editingTemplate)
        }
        .alert("Delete template?", isPresented: $showingDeleteConfirm, presenting: templateToDelete) { template in
            Button("Delete", role: .destructive) {
                withAnimation {
                    templateManager.deleteCustomTemplate(template)
                }
                templateToDelete = nil
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: { template in
            Text("\"\(template.title)\" will be removed. This can't be undone.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var customSection: some View {
        if templateManager.customTemplates.isEmpty {
            emptyCustomCard
        } else {
            sectionHeader(title: "Your Templates", count: templateManager.customTemplates.count)
            ForEach(templateManager.customTemplates) { template in
                templateCard(template, isCustom: true)
            }
        }
    }

    private var defaultsByCategory: some View {
        ForEach(MessageTemplate.MessageCategory.allCases, id: \.self) { category in
            let inCategory = templateManager.defaultTemplates.filter { $0.category == category }
            if !inCategory.isEmpty {
                sectionHeader(
                    title: category.rawValue,
                    count: inCategory.count,
                    icon: category.icon
                )
                ForEach(inCategory) { template in
                    templateCard(template, isCustom: false)
                }
            }
        }
    }

    // MARK: - Pieces

    private var emptyCustomCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(Color.electricViolet.opacity(0.8))
            Text("No custom templates yet")
                .font(.headline)
                .foregroundColor(Color.textPrimary)
            Text("Tap the + button to write your own, or browse the built-in templates below.")
                .font(.obsidianFootnote)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                editingTemplate = nil
                showingCreator = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Template")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.electricViolet)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.obsidianSurface)
        )
    }

    private func sectionHeader(title: String, count: Int, icon: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.electricViolet)
            }
            Text(title.uppercased())
                .font(.obsidianCaption)
                .fontWeight(.semibold)
                .foregroundColor(Color.textSecondary)
            Text("\(count)")
                .font(.obsidianCaption)
                .foregroundColor(Color.textMuted)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func templateCard(_ template: MessageTemplate, isCustom: Bool) -> some View {
        let previewMessage = template.message
            .replacingOccurrences(of: "{name}", with: "Alex")
            .replacingOccurrences(of: "{address}", with: "123 Main St")
            .replacingOccurrences(of: "{service_type}", with: "window cleaning")
            .replacingOccurrences(of: "{price}", with: "$150")

        return Button {
            editingTemplate = template
            showingCreator = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: template.category.icon)
                        .font(.obsidianCallout)
                        .foregroundColor(Color.electricViolet)
                        .frame(width: 28, height: 28)
                        .background(Color.electricViolet.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                            .font(.obsidianTitle)
                            .foregroundColor(Color.textPrimary)
                        HStack(spacing: 6) {
                            if isCustom {
                                pill(text: "Custom", color: .electricViolet)
                            } else {
                                pill(text: "Default", color: .statusInterested)
                            }
                            if template.isForSMS {
                                pill(text: "SMS", color: .textSecondary)
                            }
                            if template.isForEmail {
                                pill(text: "Email", color: .textSecondary)
                            }
                        }
                    }
                    Spacer()
                    if isCustom {
                        Button {
                            templateToDelete = template
                            showingDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.statusNotInterested.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(previewMessage)
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.obsidianSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.obsidianBorder.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
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
