import Foundation
import Network

enum NetworkReconnectPolicy {
    static func shouldRecover(previous: NWPath.Status?, current: NWPath.Status) -> Bool {
        guard let previous else { return false }
        return previous != .satisfied && current == .satisfied
    }
}

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    private var lastStatus: NWPath.Status?
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStarted = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let previous = self.lastStatus
            self.lastStatus = path.status

            guard NetworkReconnectPolicy.shouldRecover(previous: previous, current: path.status) else {
                if path.status != .satisfied {
                    self.reconnectWorkItem?.cancel()
                    self.reconnectWorkItem = nil
                }
                return
            }

            self.reconnectWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                DispatchQueue.main.async {
                    AppointmentManager.shared.restartFirebaseSync()
                    UserDataSyncManager.shared.startSync()
                }
            }
            self.reconnectWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.start(queue: queue)
    }

    func stop() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        monitor.cancel()
        isStarted = false
    }
}
