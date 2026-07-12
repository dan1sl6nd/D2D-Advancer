import Foundation

/// Canonical appointment payload used for CloudKit backup mirroring.
struct AppointmentSyncPayload: Sendable, Codable {
    let id: UUID
    let title: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let location: String
    let leadId: UUID?
    let calendarEventId: String?
    let appointmentType: String
    let customAppointmentTypeId: String?
    let status: String
    let updatedAt: Date

    init(
        id: UUID,
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        location: String,
        leadId: UUID?,
        calendarEventId: String?,
        appointmentType: String,
        customAppointmentTypeId: String?,
        status: String,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.leadId = leadId
        self.calendarEventId = calendarEventId
        self.appointmentType = appointmentType
        self.customAppointmentTypeId = customAppointmentTypeId
        self.status = status
        self.updatedAt = updatedAt
    }

    init(appointment: Appointment, updatedAt: Date = Date()) {
        self.id = appointment.id
        self.title = appointment.title
        self.notes = appointment.notes
        self.startDate = appointment.startDate
        self.endDate = appointment.endDate
        self.location = appointment.location
        self.leadId = appointment.leadId
        self.calendarEventId = appointment.calendarEventId
        self.appointmentType = appointment.appointmentType.rawValue
        self.customAppointmentTypeId = appointment.customAppointmentTypeId
        self.status = appointment.status.rawValue
        self.updatedAt = updatedAt
    }

    var appointment: Appointment {
        Appointment(
            id: id,
            title: title,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            location: location,
            leadId: leadId,
            calendarEventId: calendarEventId,
            appointmentType: Appointment.AppointmentType(rawValue: appointmentType) ?? .consultation,
            customAppointmentTypeId: customAppointmentTypeId,
            status: Appointment.AppointmentStatus(rawValue: status) ?? .scheduled
        )
    }
}
