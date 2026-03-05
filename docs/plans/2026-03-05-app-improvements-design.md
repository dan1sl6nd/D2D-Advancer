# App Improvements Design — 6 Features

## Summary

Six targeted improvements to the D2D Advancer app: toast + undo on quick lead creation, push notification deep links, quick-reschedule swipe on follow-ups, daily summary counter on the map, map pin clustering, and CSV lead export.

## Feature 1: Quick-Add Toast + Undo

When the user taps "Not Home" or "No Interest" on the map action bar, a floating toast appears above the action bar confirming the action: "Not Home - 123 Main St" with an Undo button. The toast auto-dismisses after 3 seconds. Tapping Undo deletes the just-created lead from Core Data and dismisses immediately.

- New `ToastView` component rendered as an overlay in MapView
- `@State` property on MapView holds the last-created lead reference
- `createQuickLead` completion sets the toast state after successful geocoding + save
- Undo: `viewContext.delete(lead)` + `viewContext.save()`
- Animation: slide up from bottom, fade out on dismiss

## Feature 2: Push Notification Deep Links

Currently `handleDefaultAction` in NotificationService logs and does nothing. Fix it to route to the correct screen.

- Extract `type` from `userInfo`:
  - `"followup"` -> extract `leadId`, call `AppRouter.shared.openLead(id:)` (uses existing `targetLeadID`)
  - `"appointment"` -> extract `appointmentId`, call `AppRouter.shared.openAppointments(id)` (already works)
- `AppRouter.openLead()` already navigates to the Leads tab and opens the detail sheet
- No new UI needed — just wiring in the notification handler

## Feature 3: Quick-Reschedule Swipe on Follow-Ups

Add `.swipeActions` to `FollowUpInteractiveRowView`:

- Swipe trailing (right): two buttons
  - "Tomorrow" (green tint) — sets follow-up to tomorrow 9:00 AM
  - "+1 Week" (purple tint) — adds 7 days to current follow-up date
- Swipe leading (left):
  - "Remove" (red, destructive) — clears follow-up date

Each action calls `lead.setFollowUpDate(newDate)`, saves context, and reschedules the notification via `NotificationService.shared.scheduleFollowUpNotification(for:)`.

## Feature 4: Daily Summary Counter

Add a "today" indicator to the existing stat chips row on the map screen.

- New computed property `todayCount`: filters leads where `createdDate >= Calendar.current.startOfDay(for: Date())`
- Rendered as a chip next to the existing "X total" chip, showing "X today"
- Uses same `statChip`-style appearance but with a distinct color or label
- Keeps existing status count chips unchanged

## Feature 5: Map Pin Clustering

Use MKMapView's native clustering support to group overlapping pins.

- In `AdvancedMapView`, when creating `MKAnnotationView` for lead pins, set `clusteringIdentifier = "lead"`
- Implement `mapView(_:viewFor:)` case for `MKClusterAnnotation`:
  - Show a circle with the member count
  - Color based on majority status among clustered leads
  - Tapping a cluster zooms the map to show individual pins
- No new dependencies — uses built-in MapKit clustering

## Feature 6: CSV Lead Export

Add an "Export Leads" card to the More screen.

- New card with icon `square.and.arrow.up`, positioned after the Overview card
- Tapping it: fetches all leads from Core Data, builds a CSV string with columns:
  Name, Address, Phone, Email, Status, Follow-Up Date, Notes, Created Date, Updated Date
- Writes CSV to a temp file, presents `UIActivityViewController` share sheet
- Handles empty state: if no leads, show an alert instead of empty CSV

## Files to Modify

- `MapView.swift` — toast overlay, today counter, undo logic
- `NotificationService.swift` — deep link routing in handleDefaultAction
- `FollowUpView.swift` — swipe actions on FollowUpInteractiveRowView
- `AdvancedMapView.swift` — clustering identifier + cluster annotation view
- `MoreView.swift` — export leads card + CSV generation

## No New Files

All features are additions to existing views. The ToastView can be a private struct inside MapView.swift.
