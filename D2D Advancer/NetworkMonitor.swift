import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    private var lastStatus: NWPath.Status = .requiresConnection

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let previous = self.lastStatus
            self.lastStatus = path.status

            // When transitioning to satisfied, trigger lightweight resyncs
            if previous != .satisfied && path.status == .satisfied {
                DispatchQueue.main.async {
                    // Restart Firestore listeners for appointments
                    AppointmentManager.shared.restartFirebaseSync()
                    // Kick off a background sync of leads/appointments
                    UserDataSyncManager.shared.startSync()
                }
            }
        }
    }

    func start() {
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

