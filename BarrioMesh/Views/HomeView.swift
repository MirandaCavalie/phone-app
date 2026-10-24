import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingChat = LaunchOptions.sheet == "chat"
    @State private var showingPaperwork = LaunchOptions.sheet == "paperwork"
    @State private var showingLog = false
    @State private var showingAlerts = LaunchOptions.sheet == "alerts"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero

                    if let latest = model.officialAlerts.first {
                        OfficialAlertCard(alert: latest.alert, assessment: latest.assessment)
                    }

                    NavigationLink {
                        AlertsView(monitor: model.hazardMonitor)
                    } label: {
                        LiveAlertsRow(monitor: model.hazardMonitor)
                    }
                    .buttonStyle(.plain)

                    ForEach(agreements) { summary in
                        AgreementCard(summary: summary)
                    }

                    ForEach(model.memory.pending) { pending in
                        PendingCard(pending: pending)
                    }

                    if model.memory.emergencyActive {
                        RowButton(
                            icon: "doc.text.fill",
                            title: t("Trámites listos", "Calls & forms ready"),
                            subtitle: t("Guion para el \(model.profile.country.emergencyNumber) y reporte en PDF", "\(model.profile.country.emergencyNumber) call script and PDF report")
                        ) { showingPaperwork = true }
                    } else {
                        TodayCard()
                        ForEach(model.suggestions.prefix(3)) { suggestion in
                            SuggestionCard(suggestion: suggestion)
                        }
                        PreparednessCard()
                    }

                    if !model.familyCheckIns.isEmpty {
                        FamilyStrip()
                    }

                    activity
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Faro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingChat = true
                    } label: {
                        Label(t("Háblale a Faro", "Talk to Faro"), systemImage: "waveform.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingChat) { AskFaroView() }
            .sheet(isPresented: $showingPaperwork) { PaperworkView() }
            .sheet(isPresented: $showingLog) { ActivityLogView() }
            .sheet(isPresented: $showingAlerts) { NavigationStack { AlertsView(monitor: model.hazardMonitor) } }
        }
    }

    private var agreements: [AppModel.MatchSummary] {
        model.matchSummaries.filter { $0.status == .accepted && $0.requiredPeers.contains(model.deviceID) }
    }

    // MARK: Hero

    private var statusLine: String {
        var parts = [model.effectiveConnectivity == .online ? t("Con internet", "Online") : t("Sin internet", "Offline")]
        let real = model.peerSession.connectedPeerNames.count
        let simulated = model.simulatedNeighborCount
        parts.append(simulated > 0
                     ? t("\(real + simulated) cerca (sim.)", "\(real + simulated) nearby (sim.)")
                     : t("\(real) cerca", "\(real) nearby"))
        let unsent = model.memory.unsentOutbox.count
        if unsent > 0 { parts.append(t("\(unsent) por enviar", "\(unsent) to send")) }
        return parts.joined(separator: " · ")
    }

    private var hero: some View {
        let emergency = model.memory.emergencyActive
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FaroMark(size: 44, emergency: emergency)
                VStack(alignment: .leading, spacing: 2) {
                    Text(emergency ? t("Modo emergencia", "Emergency mode") : t("Todo tranquilo", "All calm"))
                        .font(.title3.weight(.bold))
                    Text(statusLine)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            if emergency {
                MeshRadarView(nodes: model.meshNodes)
                    .frame(height: 170)
            }

            Button {
                withAnimation(.snappy) { model.setEmergency(!emergency) }
            } label: {
                Text(emergency ? t("Volver a modo normal", "Back to normal") : t("Activar modo emergencia", "Start emergency mode"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(emergency ? .white.opacity(0.22) : FaroTheme.ember)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FaroTheme.heroGradient(emergency: emergency)))
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t("Lo que hizo Faro", "What Faro did"))
                    .font(.headline)
                Spacer()
                if model.memory.log.count > 5 {
                    Button(t("Ver todo", "See all")) { showingLog = true }
                        .font(.subheadline)
                }
            }
            .padding(.top, 6)

            if model.memory.log.isEmpty {
                Text(t("Nada todavía. Si pasa algo, me activo solo.", "Nothing yet. If something happens, I'll step in."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .faroCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.memory.log.prefix(5)) { entry in
                        ActivityRow(entry: entry)
                    }
                }
                .faroCard()
            }
        }
    }
}

// MARK: - Cards

private struct RowButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(FaroTheme.beam)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .faroCard()
        }
        .buttonStyle(.plain)
    }
}

/// The morning briefing: one glance at the day, readable or spoken.
private struct TodayCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let briefing = model.briefing
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(briefing.greeting).font(.headline)
                Spacer()
                Button {
                    model.narrator.speak(briefing.spoken, country: model.profile.country)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("Escuchar resumen", "Listen to briefing"))
            }
            ForEach(briefing.lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .faroCard(tint: FaroTheme.beam)
    }
}

/// Something the agent offers to handle: one tap to do it, one to hide it.
private struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    let suggestion: Suggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title).font(.subheadline.weight(.semibold))
                if !suggestion.detail.isEmpty {
                    Text(suggestion.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Button(suggestion.actionLabel) {
                        withAnimation { model.perform(suggestion) { openURL($0) } }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(t("Ahora no", "Not now")) {
                        withAnimation { model.dismiss(suggestion) }
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .faroCard()
    }
}

private struct LiveAlertsRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var monitor: HazardMonitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(FaroTheme.beam)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.effectiveConnectivity == .online)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(t("Alertas en vivo · \(model.profile.approximateLocation.label)", "Live alerts · \(model.profile.approximateLocation.label)"))
                    .font(.subheadline.weight(.semibold))
                Group {
                    if let date = monitor.lastUpdate {
                        Text(t("\(monitor.regional.count) eventos en 24 h · ", "\(monitor.regional.count) events in 24 h · ")) + Text(date, style: .relative)
                    } else {
                        Text(model.effectiveConnectivity == .online ? t("Conectando a 4 fuentes…", "Connecting to 4 sources…") : t("Sin internet", "Offline"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .faroCard()
    }
}

private struct PendingCard: View {
    @EnvironmentObject private var model: AppModel
    let pending: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pending.title)
                .font(.subheadline.weight(.semibold))
            if !pending.detail.isEmpty {
                Text(pending.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Button { withAnimation { model.approve(pending) } } label: {
                    Text(t("Sí", "Yes")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { withAnimation { model.dismiss(pending) } } label: {
                    Text(t("Ahora no", "Not now")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .faroCard(tint: FaroTheme.beam)
    }
}

private struct AgreementCard: View {
    @EnvironmentObject private var model: AppModel
    let summary: AppModel.MatchSummary

    var body: some View {
        let need = summary.candidate.need
        let iReceive = need.authorID == model.deviceID
        let other = iReceive ? summary.candidate.offer.authorName : need.authorName

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: need.resource.systemImage)
                .font(.title3)
                .foregroundStyle(FaroTheme.safe)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                if let terms = summary.negotiation.agreedTerms {
                    Text(iReceive
                         ? t("Recibes \(need.resource.amount(terms.quantity))", "You get \(need.resource.amount(terms.quantity))")
                         : t("Entregas \(need.resource.amount(terms.quantity))", "You give \(need.resource.amount(terms.quantity))"))
                        .font(.subheadline.weight(.semibold))
                    Text("\(other) · \(terms.meetingPoint) · \(terms.meetAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if model.hasCompleted(summary) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(FaroTheme.safe)
            } else {
                Button(t("Hecho", "Done")) { model.complete(summary) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .faroCard(tint: FaroTheme.safe)
    }
}

private struct PreparednessCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let report = model.profile.preparedness
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(report.score) / 100)
                    .stroke(FaroTheme.beam, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(report.score)").font(.subheadline.weight(.bold))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(t("Preparación del hogar", "Household readiness"))
                    .font(.subheadline.weight(.semibold))
                Text(report.gaps.first ?? t("Todo listo.", "All set."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .faroCard()
    }
}

private struct FamilyStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.familyCheckIns) { checkIn in
                HStack(spacing: 8) {
                    Circle()
                        .fill(checkIn.status == .safe ? FaroTheme.safe : FaroTheme.ember)
                        .frame(width: 8, height: 8)
                    Text("\(checkIn.authorName): \(checkIn.status.inlineName)")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(checkIn.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .faroCard(tint: FaroTheme.safe)
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(entry.kind.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// The full log, for when someone wants every step and its reason.
struct ActivityLogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.memory.log) { entry in
                ActivityRow(entry: entry)
            }
            .navigationTitle(t("Lo que hizo Faro", "What Faro did"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("Listo", "Done")) { dismiss() } }
            }
        }
    }
}

private struct OfficialAlertCard: View {
    let alert: HazardAlert
    let assessment: HazardAssessment

    private var color: Color {
        switch assessment.level {
        case .danger: FaroTheme.ember
        case .warning: .orange
        default: .yellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: alert.kind.systemImage)
                Text(alert.isSimulated ? "\(alert.source) · \(t("simulada", "simulated"))" : alert.source)
                Spacer()
                Text(alert.occurredAt, style: .relative)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)

            Text(assessment.headline)
                .font(.headline)
            Text(assessment.advice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let url = URL(string: alert.url), !alert.isSimulated {
                Link(t("Ver en \(alert.source)", "View on \(alert.source)"), destination: url)
                    .font(.caption)
            }
        }
        .faroCard(tint: color)
    }
}
