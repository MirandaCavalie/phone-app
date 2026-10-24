import Foundation
import UserNotifications

/// While the phone has internet, polls official and scientific real-time feeds
/// (USGS, EMSC, GDACS, NOAA PTWC) so the agent hears about a quake, tsunami, flood or
/// eruption before the network goes down, and relays it to phones that are offline.
@MainActor
final class HazardMonitor: ObservableObject {
    struct SourceStatus: Equatable {
        var lastSuccess: Date?
        var lastError: String?
        var eventCount = 0
    }

    /// Everything recent in the region, relevant or not, for the live feed screen. Never gossiped.
    @Published private(set) var regional: [HazardAlert] = []
    @Published private(set) var status: [HazardSource: SourceStatus] = [:]

    var onAlerts: (([HazardAlert]) -> Void)?
    var isOnline: () -> Bool = { true }
    var home: () -> GeoPoint = { GeoPoint(latitude: 4.711, longitude: -74.072) }

    private var tasks: [HazardSource: Task<Void, Never>] = [:]
    private var relayedBy = ""

    func start(relayedBy agentID: String) {
        relayedBy = agentID
        for source in HazardSource.allCases where tasks[source] == nil {
            tasks[source] = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.fetch(source)
                    try? await Task.sleep(for: .seconds(source.pollInterval))
                }
            }
        }
    }

    func refreshAll() {
        for source in HazardSource.allCases { Task { await fetch(source) } }
    }

    var lastUpdate: Date? { status.values.compactMap(\.lastSuccess).max() }

    private func fetch(_ source: HazardSource) async {
        guard isOnline() else { return }
        let home = home()
        var request = URLRequest(url: source.url(around: home), timeoutInterval: source == .gdacs ? 30 : 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Faro/1.0 (personal emergency agent)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // GDACS answers 204 when there is nothing to report.
            let alerts = code == 204 ? [] : try source.parse(data, relayedBy: relayedBy)
            guard code == 200 || code == 204 else { throw URLError(.badServerResponse) }
            status[source] = SourceStatus(lastSuccess: Date(), lastError: nil, eventCount: alerts.count)
            mergeRegional(alerts, home: home)
            onAlerts?(alerts)
        } catch {
            var current = status[source] ?? SourceStatus()
            current.lastError = error.localizedDescription
            status[source] = current
        }
    }

    private func mergeRegional(_ alerts: [HazardAlert], home: GeoPoint) {
        let dayAgo = Date().addingTimeInterval(-24 * 3_600)
        var merged = regional.filter { $0.occurredAt > dayAgo }
        for alert in alerts where alert.occurredAt > dayAgo && alert.epicenter.distanceKm(to: home) < 1_500 {
            if !merged.contains(where: { $0.isSameEvent(as: alert) }) { merged.append(alert) }
        }
        regional = merged.sorted { $0.occurredAt > $1.occurredAt }
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
