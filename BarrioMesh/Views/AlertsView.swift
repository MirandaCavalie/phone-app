import SwiftUI

/// Live official alerts for the household's region, and the health of each source.
struct AlertsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var monitor: HazardMonitor

    var body: some View {
        List {
            if !model.officialAlerts.isEmpty {
                Section(t("Para ti", "For you")) {
                    ForEach(model.officialAlerts, id: \.alert.id) { item in
                        AlertRow(alert: item.alert, headline: item.assessment.headline, detail: item.assessment.advice, level: item.assessment.level)
                    }
                }
            }

            Section {
                if monitor.regional.isEmpty {
                    Text(model.effectiveConnectivity == .online
                         ? t("Sin eventos en las últimas 24 h cerca de \(model.profile.approximateLocation.label).", "No events in the last 24 h near \(model.profile.approximateLocation.label).")
                         : t("Sin internet: muestro solo lo que llegó por la red de vecinos.", "Offline: showing only what neighbors relayed."))
                        .foregroundStyle(.secondary)
                }
                ForEach(monitor.regional.prefix(40)) { alert in
                    let assessment = HazardAssessment.assess(alert, home: model.profile.approximateLocation.point)
                    AlertRow(
                        alert: alert,
                        headline: alert.kind == .earthquake ? "M\(String(format: "%.1f", alert.magnitude)) · \(Int(assessment.distanceKm.rounded())) km" : "\(alert.kind.displayName) · \(Int(assessment.distanceKm.rounded())) km",
                        detail: alert.place,
                        level: assessment.level
                    )
                }
            } header: {
                Text(t("Actividad en tu región (24 h)", "Activity in your region (24 h)"))
            }

            Section {
                ForEach(HazardSource.allCases, id: \.self) { source in
                    let status = monitor.status[source]
                    HStack {
                        Circle()
                            .fill(status?.lastError != nil && status?.lastSuccess == nil ? FaroTheme.ember : status?.lastSuccess != nil ? FaroTheme.safe : .gray)
                            .frame(width: 8, height: 8)
                        Text(source.displayName).font(.subheadline)
                        Spacer()
                        if let date = status?.lastSuccess {
                            Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(t("Fuentes en vivo", "Live sources"))
            } footer: {
                Text(t("Fuentes abiertas y oficiales, sin clave. Las alertas relevantes se retransmiten firmadas por Bluetooth a vecinos sin señal.",
                       "Open, official sources, no API key. Relevant alerts are relayed, signed, over Bluetooth to neighbors without signal."))
            }
        }
        .navigationTitle(t("Alertas en vivo", "Live alerts"))
        .refreshable { monitor.refreshAll() }
    }
}

private struct AlertRow: View {
    let alert: HazardAlert
    let headline: String
    let detail: String
    let level: HazardAssessment.Level

    private var color: Color {
        switch level {
        case .danger: FaroTheme.ember
        case .warning: .orange
        case .watch: .yellow
        case .ignore: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.kind.systemImage)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(alert.isSimulated ? "SIM" : alert.source).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(alert.occurredAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
