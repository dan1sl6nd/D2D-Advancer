import Combine
import CoreData
import Foundation

struct LeadOverviewMetrics: Equatable, Sendable {
    var totalLeadCount = 0
    var todayLeadCount = 0
    var todayInterestedCount = 0
    var todayNotHomeCount = 0
    var todaySoldCount = 0
    var followUpsDueCount = 0
    var followUpsTotalCount = 0

    static let empty = LeadOverviewMetrics()
}

@MainActor
final class LeadOverviewMetricsStore: ObservableObject {
    static let shared = LeadOverviewMetricsStore()

    @Published private(set) var metrics: LeadOverviewMetrics = .empty

    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var saveObserver: NSObjectProtocol?

    private init() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard Self.containsLeadChanges(notification) else { return }
            Task { @MainActor in
                self?.scheduleRefresh(after: 0.2)
            }
        }
        scheduleRefresh(after: 0.5)
    }

    deinit {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    func refresh() {
        scheduleRefresh(after: 0)
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled,
                  PersistenceController.shared.hasPersistentStore else {
                if generation == refreshGeneration {
                    refreshTask = nil
                }
                return
            }

            let nextMetrics = await Self.fetchMetrics(
                from: PersistenceController.shared.container,
                now: Date()
            )
            guard !Task.isCancelled, generation == refreshGeneration else {
                return
            }
            if metrics != nextMetrics {
                metrics = nextMetrics
            }
            refreshTask = nil
        }
    }

    private static func fetchMetrics(
        from container: NSPersistentContainer,
        now: Date
    ) async -> LeadOverviewMetrics {
        await withCheckedContinuation { continuation in
            container.performBackgroundTask { context in
                context.undoManager = nil
                let startOfDay = Calendar.current.startOfDay(for: now)

                func count(_ predicate: NSPredicate? = nil) -> Int {
                    let request: NSFetchRequest<Lead> = Lead.fetchRequest(in: context)
                    request.predicate = predicate
                    request.includesPendingChanges = false
                    request.includesSubentities = false
                    return (try? context.count(for: request)) ?? 0
                }

                func todayStatusPredicate(_ status: String) -> NSPredicate {
                    NSCompoundPredicate(andPredicateWithSubpredicates: [
                        NSPredicate(format: "createdDate >= %@", startOfDay as NSDate),
                        NSPredicate(format: "status == %@", status)
                    ])
                }

                continuation.resume(returning: LeadOverviewMetrics(
                    totalLeadCount: count(),
                    todayLeadCount: count(NSPredicate(format: "createdDate >= %@", startOfDay as NSDate)),
                    todayInterestedCount: count(todayStatusPredicate("interested")),
                    todayNotHomeCount: count(todayStatusPredicate("not_home")),
                    todaySoldCount: count(todayStatusPredicate("converted")),
                    followUpsDueCount: count(Lead.Status.activeFollowUpPredicate(dueBefore: now)),
                    followUpsTotalCount: count(Lead.Status.activeFollowUpPredicate)
                ))
            }
        }
    }

    private nonisolated static func containsLeadChanges(_ notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo else { return false }
        return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Lead }
        }
    }
}
