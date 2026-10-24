import Foundation
import UserNotifications

/// While the phone has internet, polls the USGS real-time feed once a minute so the agent
/// hears about a dangerous quake or tsunami before the network goes down.
@MainActor
final class HazardMonitor {
    var onAlerts: (([HazardAlert]) -> Void)?
    var isOnline: () -> Bool = { true }

    private var task: Task<Void, Never>?
    private var lastFetch: Date?

    func start(relayedBy agentID: String) {
        guard task == nil else { return }
        task = Task { [weak self] in
            // On launch, look back a day for big events; afterwards, every minute, the last hour.
            await self?.fetch(USGSFeed.significantPastDay, relayedBy: agentID)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.fetch(USGSFeed.pastHour, relayedBy: agentID)
            }
        }
    }

    func refreshNow(relayedBy agentID: String) {
        Task { await fetch(USGSFeed.pastHour, relayedBy: agentID) }
    }

    private func fetch(_ url: URL, relayedBy agentID: String) async {
        guard isOnline() else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let alerts = try? USGSFeed.parse(data, relayedBy: agentID) else { return }
        lastFetch = Date()
        onAlerts?(alerts)
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ assessment: HazardAssessment, alert: HazardAlert) {
        let content = UNMutableNotificationContent()
        content.title = assessment.headline
        content.body = "\(alert.place). \(assessment.advice)"
        content.sound = assessment.level == .danger ? .defaultCritical : .default
        let request = UNNotificationRequest(identifier: alert.eventID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
