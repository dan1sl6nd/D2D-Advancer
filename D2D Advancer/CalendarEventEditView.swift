import SwiftUI
import EventKit
import EventKitUI

struct CalendarEventEditView: UIViewControllerRepresentable {
    let appointment: Appointment
    let onSaved: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.editViewDelegate = context.coordinator
        let store = EKEventStore()
        controller.eventStore = store

        // If existing eventId exists and can be loaded, edit that event; else create new
        if let eventId = appointment.calendarEventId, let existing = store.event(withIdentifier: eventId) {
            controller.event = existing
        } else {
            let event = EKEvent(eventStore: store)
            event.title = appointment.title
            event.location = appointment.location
            event.notes = appointment.notes
            event.startDate = appointment.startDate
            event.endDate = appointment.endDate
            event.calendar = store.defaultCalendarForNewEvents
            controller.event = event
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        // No-op
    }

    class Coordinator: NSObject, EKEventEditViewDelegate {
        let parent: CalendarEventEditView
        init(_ parent: CalendarEventEditView) { self.parent = parent }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            switch action {
            case .saved:
                if let id = controller.event?.eventIdentifier {
                    parent.onSaved(id)
                } else {
                    parent.onCancel()
                }
            case .canceled, .deleted:
                parent.onCancel()
            @unknown default:
                parent.onCancel()
            }
            controller.dismiss(animated: true)
        }
    }
}

