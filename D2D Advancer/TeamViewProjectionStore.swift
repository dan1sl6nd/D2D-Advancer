import Combine
import Foundation

struct TeamFollowUpProjection: Equatable, Sendable {
    var leads: [TeamLead]
    var members: [TeamMember]
}

@MainActor
final class TeamFollowUpProjectionStore: ObservableObject {
    static let shared = TeamFollowUpProjectionStore()

    @Published private(set) var projection: TeamFollowUpProjection

    private var cancellable: AnyCancellable?

    private init() {
        let service = TeamFirebaseService.shared
        projection = TeamFollowUpProjection(
            leads: service.teamLeads,
            members: service.teamMembers
        )

        cancellable = Publishers.CombineLatest(
            service.$teamLeads.removeDuplicates(),
            service.$teamMembers.removeDuplicates()
        )
        .map { leads, members in
            TeamFollowUpProjection(leads: leads, members: members)
        }
        .removeDuplicates()
        .sink { [weak self] projection in
            self?.projection = projection
        }
    }
}

struct TeamOverviewProjection: Equatable, Sendable {
    var currentMember: TeamMember?
    var bookings: [TeamBooking]
}

@MainActor
final class TeamOverviewProjectionStore: ObservableObject {
    static let shared = TeamOverviewProjectionStore()

    @Published private(set) var projection: TeamOverviewProjection

    private var cancellable: AnyCancellable?

    private init() {
        let service = TeamFirebaseService.shared
        projection = TeamOverviewProjection(
            currentMember: service.currentMember,
            bookings: service.teamBookings
        )

        cancellable = Publishers.CombineLatest(
            service.$currentMember.removeDuplicates(),
            service.$teamBookings.removeDuplicates()
        )
        .map { member, bookings in
            TeamOverviewProjection(currentMember: member, bookings: bookings)
        }
        .removeDuplicates()
        .sink { [weak self] projection in
            self?.projection = projection
        }
    }
}

@MainActor
final class TeamShortcutProjectionStore: ObservableObject {
    static let shared = TeamShortcutProjectionStore()

    @Published private(set) var summary: TeamWorkspaceSurfaceSummary?

    private let service: TeamFirebaseService
    private var cancellable: AnyCancellable?

    private init() {
        service = TeamFirebaseService.shared
        summary = Self.makeSummary(from: service)

        let changes: [AnyPublisher<Void, Never>] = [
            service.$activeTeam.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$currentMember.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$teamMembers.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$teamLeads.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$teamBookings.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$dutySessions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.$ownerNotifications.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]

        cancellable = Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.refresh()
            }
    }

    private func refresh() {
        let nextSummary = Self.makeSummary(from: service)
        guard nextSummary != summary else { return }
        summary = nextSummary
    }

    private static func makeSummary(from service: TeamFirebaseService) -> TeamWorkspaceSurfaceSummary? {
        TeamWorkspaceSurfaceSummary.makeShortcut(
            team: service.activeTeam,
            currentMember: service.currentMember,
            members: service.teamMembers,
            leads: service.teamLeads,
            bookings: service.teamBookings,
            dutySessions: service.dutySessions,
            ownerNotifications: service.ownerNotifications
        )
    }
}
