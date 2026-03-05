# App Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 6 features: toast+undo on quick leads, notification deep links, follow-up quick-reschedule, daily counter, pin clustering, CSV export.

**Architecture:** Each feature is a self-contained task modifying 1-2 existing files. No new files needed. All changes use existing patterns (Core Data, AppRouter, MKMapView delegate).

**Tech Stack:** SwiftUI, MapKit, Core Data, UserNotifications

---

### Task 1: Quick-add toast + undo

**Files:**
- Modify: `D2D Advancer/MapView.swift`

**Step 1: Add toast state properties after the existing `@State` declarations (around line 16)**

```swift
// Add after line 17 (paywallManager)
@State private var toastLead: Lead?
@State private var toastMessage: String = ""
@State private var showToast = false
```

**Step 2: Add the toast view component (after the `statChip` function, around line 555)**

```swift
private var toastOverlay: some View {
    VStack {
        Spacer()
        if showToast {
            HStack(spacing: 12) {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Button("Undo") {
                    undoQuickLead()
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.electricViolet)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast)
}

private func showQuickLeadToast(status: Lead.Status, address: String, lead: Lead) {
    toastLead = lead
    toastMessage = "\(status.displayName) -- \(address)"
    withAnimation {
        showToast = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        withAnimation {
            showToast = false
        }
        toastLead = nil
    }
}

private func undoQuickLead() {
    if let lead = toastLead {
        viewContext.delete(lead)
        try? viewContext.save()
    }
    withAnimation {
        showToast = false
    }
    toastLead = nil
}
```

**Step 3: Add the toast overlay to the ZStack in `body` (after `overlayControls`, around line 44)**

Find:
```swift
        ZStack {
                mapView
                overlayControls
```

Replace with:
```swift
        ZStack {
                mapView
                overlayControls
                toastOverlay
```

**Step 4: Update `createQuickLeadAt` to trigger the toast after saving (around line 634)**

Find:
```swift
                do {
                    try viewContext.save()
                    print("✅ Quick lead created: \(status.displayName) at \(Utilities.redactedText(addressString))")

                } catch {
```

Replace with:
```swift
                do {
                    try viewContext.save()
                    print("✅ Quick lead created: \(status.displayName) at \(Utilities.redactedText(addressString))")
                    showQuickLeadToast(status: status, address: addressString, lead: newLead)
                } catch {
```

**Step 5: Build and verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 6: Deploy and test**

```bash
xcrun simctl terminate booted dan1sland.D2D-Advancer 2>/dev/null
xcrun simctl install 2097FCC2-01C1-4780-8ED8-3C21E6331D04 "/tmp/d2d-build/Build/Products/Debug-iphonesimulator/D2D Advancer.app"
xcrun simctl launch 2097FCC2-01C1-4780-8ED8-3C21E6331D04 dan1sland.D2D-Advancer
```

Expected: Tap "Not Home" on map, see toast with address and Undo button.

**Step 7: Commit**

```bash
git add "D2D Advancer/MapView.swift"
git commit -m "feat(map): add quick-add toast with undo on lead creation"
```

---

### Task 2: Push notification deep links

**Files:**
- Modify: `D2D Advancer/NotificationService.swift:473-478`

**Step 1: Replace `handleDefaultAction` to route based on notification type**

Find:
```swift
    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        // Default action when notification is tapped.
        // Avoid logging full payload because it may contain sensitive lead metadata.
        let type = userInfo["type"] as? String ?? "unknown"
        print("Default notification action triggered (type: \(type))")
    }
```

Replace with:
```swift
    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? "unknown"
        print("Default notification action triggered (type: \(type))")

        if let leadIdStr = userInfo["leadId"] as? String, let uuid = UUID(uuidString: leadIdStr) {
            DispatchQueue.main.async {
                AppRouter.shared.openLead(uuid)
            }
        } else if let apptIdStr = userInfo["appointmentId"] as? String, let uuid = UUID(uuidString: apptIdStr) {
            DispatchQueue.main.async {
                AppRouter.shared.openAppointments(uuid)
            }
        }
    }
```

**Step 2: Build to verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "D2D Advancer/NotificationService.swift"
git commit -m "feat(notifications): deep link to lead/appointment on tap"
```

---

### Task 3: Quick-reschedule swipe on follow-ups

**Files:**
- Modify: `D2D Advancer/FollowUpView.swift` (FollowUpInteractiveRowView, around line 336)

**Step 1: Add swipe actions to the row view**

Find (in `FollowUpInteractiveRowView`):
```swift
        .surfaceCard()
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
```

Replace with:
```swift
        .surfaceCard()
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                rescheduleTo(days: 7)
            } label: {
                Label("+1 Week", systemImage: "calendar.badge.plus")
            }
            .tint(Color.electricViolet)

            Button {
                rescheduleTo(days: 1)
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(Color.statusInterested)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "bell.slash")
            }
        }
```

**Step 2: Add the `rescheduleTo` helper inside `FollowUpInteractiveRowView` (after `timeStatus` function, around line 415)**

```swift
    private func rescheduleTo(days: Int) {
        let calendar = Calendar.current
        let baseDate: Date
        if days == 1 {
            // Tomorrow at 9:00 AM
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
            baseDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        } else {
            // Add days to current follow-up date (or now if nil)
            let from = lead.followUpDate ?? Date()
            baseDate = calendar.date(byAdding: .day, value: days, to: from)!
        }
        lead.setFollowUpDate(baseDate)
        NotificationService.shared.scheduleFollowUpNotification(for: lead)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
```

**Step 3: Build to verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Deploy and test**

```bash
xcrun simctl terminate booted dan1sland.D2D-Advancer 2>/dev/null
xcrun simctl install 2097FCC2-01C1-4780-8ED8-3C21E6331D04 "/tmp/d2d-build/Build/Products/Debug-iphonesimulator/D2D Advancer.app"
xcrun simctl launch 2097FCC2-01C1-4780-8ED8-3C21E6331D04 dan1sland.D2D-Advancer
```

Expected: Follow Up tab shows swipe actions (Tomorrow, +1 Week on right; Remove on left).

**Step 5: Commit**

```bash
git add "D2D Advancer/FollowUpView.swift"
git commit -m "feat(followup): add quick-reschedule swipe actions"
```

---

### Task 4: Daily summary counter on map

**Files:**
- Modify: `D2D Advancer/MapView.swift`

**Step 1: Add todayCount computed property (after soldCount, around line 39)**

```swift
private var todayCount: Int {
    let startOfDay = Calendar.current.startOfDay(for: Date())
    return leads.filter { ($0.createdDate ?? .distantPast) >= startOfDay }.count
}
```

**Step 2: Update `statChipsRow` to include a "today" chip**

Find:
```swift
            Spacer()
            Text("\(leads.count) total")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial)
                .clipShape(Capsule())
```

Replace with:
```swift
            Spacer()
            if todayCount > 0 {
                Text("\(todayCount) today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.statusInterested)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
            }
            Text("\(leads.count) total")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial)
                .clipShape(Capsule())
```

**Step 3: Build to verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add "D2D Advancer/MapView.swift"
git commit -m "feat(map): add daily summary counter chip"
```

---

### Task 5: Map pin clustering

**Files:**
- Modify: `D2D Advancer/AdvancedMapView.swift:259-291`

**Step 1: Add clusteringIdentifier to the annotation view (around line 268)**

Find:
```swift
            annotationView.annotation = annotation
            annotationView.canShowCallout = true
```

Replace with:
```swift
            annotationView.annotation = annotation
            annotationView.canShowCallout = true
            annotationView.clusteringIdentifier = "LeadCluster"
```

**Step 2: Handle the cluster annotation at the top of `mapView(_:viewFor:)` (around line 260)**

Find:
```swift
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let leadAnnotation = annotation as? LeadMapAnnotation else {
                return nil
            }
```

Replace with:
```swift
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Handle cluster annotations
            if let cluster = annotation as? MKClusterAnnotation {
                let clusterID = "LeadCluster"
                let clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: clusterID) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: clusterID)
                clusterView.annotation = cluster
                clusterView.markerTintColor = .systemPurple
                clusterView.glyphText = "\(cluster.memberAnnotations.count)"
                return clusterView
            }

            guard let leadAnnotation = annotation as? LeadMapAnnotation else {
                return nil
            }
```

**Step 3: Build to verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Deploy and test**

```bash
xcrun simctl terminate booted dan1sland.D2D-Advancer 2>/dev/null
xcrun simctl install 2097FCC2-01C1-4780-8ED8-3C21E6331D04 "/tmp/d2d-build/Build/Products/Debug-iphonesimulator/D2D Advancer.app"
xcrun simctl launch 2097FCC2-01C1-4780-8ED8-3C21E6331D04 dan1sland.D2D-Advancer
```

Expected: Zooming out on the map clusters nearby pins into a purple bubble with a count.

**Step 5: Commit**

```bash
git add "D2D Advancer/AdvancedMapView.swift"
git commit -m "feat(map): add pin clustering for overlapping leads"
```

---

### Task 6: CSV lead export

**Files:**
- Modify: `D2D Advancer/MoreView.swift`

**Step 1: Add export state and function to MoreView (add state after line 13)**

```swift
@State private var showingExportSheet = false
@State private var exportFileURL: URL?
```

**Step 2: Add the Export Leads card in the card list (after the Overview NavigationLink, around line 36)**

```swift
                            // Export Leads Card
                            Button(action: {
                                exportLeadsToCSV()
                            }) {
                                MoreCardView(
                                    icon: "square.and.arrow.up",
                                    iconColor: Color.dataCyan,
                                    title: "Export Leads",
                                    subtitle: "Download all leads as CSV",
                                    showChevron: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .sheet(isPresented: $showingExportSheet) {
                                if let url = exportFileURL {
                                    ShareSheet(activityItems: [url])
                                }
                            }
```

**Step 3: Add the export function and ShareSheet at the bottom of MoreView (before the closing brace, around line 189)**

```swift
    private func exportLeadsToCSV() {
        let fetchRequest: NSFetchRequest<Lead> = Lead.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Lead.createdDate, ascending: false)]

        guard let leads = try? viewContext.fetch(fetchRequest), !leads.isEmpty else {
            return
        }

        var csv = "Name,Address,Phone,Email,Status,Follow-Up Date,Notes,Created,Updated\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        for lead in leads {
            let name = csvEscape(lead.name ?? "")
            let address = csvEscape(lead.address ?? "")
            let phone = csvEscape(lead.phone ?? "")
            let email = csvEscape(lead.email ?? "")
            let status = lead.leadStatus.displayName
            let followUp = lead.followUpDate.map { dateFormatter.string(from: $0) } ?? ""
            let notes = csvEscape(lead.notes ?? "")
            let created = lead.createdDate.map { dateFormatter.string(from: $0) } ?? ""
            let updated = lead.updatedDate.map { dateFormatter.string(from: $0) } ?? ""
            csv += "\(name),\(address),\(phone),\(email),\(status),\(followUp),\(notes),\(created),\(updated)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("D2D_Leads_Export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportFileURL = tempURL
        showingExportSheet = true
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
```

**Step 4: Add ShareSheet UIViewControllerRepresentable (after the MoreView struct, before OverviewContentView)**

Find:
```swift
    // MARK: - Pro Plan Helpers
    // Removed plan helpers; monetization disabled
}
```

Replace with:
```swift
    // MARK: - Pro Plan Helpers
    // Removed plan helpers; monetization disabled
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

**Step 5: Build to verify**

```bash
cd "/Users/dan1sland/Documents/XCode Projects/D2D Advancer"
xcodebuild -scheme "D2D Advancer" -destination 'id=2097FCC2-01C1-4780-8ED8-3C21E6331D04' -derivedDataPath /tmp/d2d-build build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 6: Deploy and test**

```bash
xcrun simctl terminate booted dan1sland.D2D-Advancer 2>/dev/null
xcrun simctl install 2097FCC2-01C1-4780-8ED8-3C21E6331D04 "/tmp/d2d-build/Build/Products/Debug-iphonesimulator/D2D Advancer.app"
xcrun simctl launch 2097FCC2-01C1-4780-8ED8-3C21E6331D04 dan1sland.D2D-Advancer
```

Expected: More tab shows "Export Leads" card. Tapping it opens share sheet with CSV file.

**Step 7: Commit**

```bash
git add "D2D Advancer/MoreView.swift"
git commit -m "feat(more): add CSV lead export"
```
