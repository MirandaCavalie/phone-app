import Foundation
import Network

/// Watches whether the phone can reach the internet. Losing it is the agent's cue
/// to switch into emergency mode; getting it back is the cue to flush the outbox.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var hasInternet = true

    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "faro.connectivity")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.hasInternet != online else { return }
                self.hasInternet = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: queue)
    }
}
