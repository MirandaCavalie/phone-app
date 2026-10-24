import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingChat = LaunchOptions.sheet == "chat"
    @State private var showingPaperwork = LaunchOptions.sheet == "paperwork"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero

                    if !agreements.isEmpty {
                        SectionHeader(title: "Encuentros acordados")
                        ForEach(agreements) { summary in
                            AgreementCard(summary: summary)
                        }
                    }

                    if !model.memory.pending.isEmpty {
                        SectionHeader(title: "Faro necesita tu OK", subtitle: "Esto está fuera de lo que lo autorizaste a hacer solo.")
                        ForEach(model.memory.pending) { pending in
                            PendingCard(pending: pending)
                        }
                    }

                    if model.memory.emergencyActive {
                        Button {
                            showingPaperwork = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "doc.badge.ellipsis")
                                    .font(.title2)
                                    .foregroundStyle(FaroTheme.beam)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Trámites listos").font(.headline)
                                    Text("Guion para llamar al \(model.profile.country.emergencyNumber) y reporte de afectación prellenado.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .faroCard()
                        }
                        .buttonStyle(.plain)
                    } else {
                        PreparednessCard()
                    }

                    if !model.familyCheckIns.isEmpty {
                        FamilyStrip()
                    }

                    SectionHeader(title: "Lo que hizo Faro", subtitle: "Cada acción del agente, con su razón.")
                    if model.memory.log.isEmpty {
                        Text("Todavía nada. Si se cae internet, Faro activa el modo emergencia y empieza a trabajar por ti.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .faroCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.memory.log.prefix(40)) { entry in
                                ActivityRow(entry: entry)
                            }
                        }
                        .faroCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Faro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingChat = true
                    } label: {
                        Label("Háblale a Faro", systemImage: "bubble.left.and.text.bubble.right.fill")
                    }
                }
            }
            .sheet(isPresented: $showingChat) {
                AskFaroView()
            }
            .sheet(isPresented: $showingPaperwork) {
                PaperworkView()
            }
        }
    }

    private var agreements: [AppModel.MatchSummary] {
        model.matchSummaries.filter {
            $0.status == .accepted && $0.requiredPeers.contains(model.deviceID)
        }
    }

    private var nearbyText: String {
        let real = model.peerSession.connectedPeerNames.count
        let simulated = model.simulatedNeighborCount
        if simulated > 0, real == 0 { return "\(simulated) simulados" }
        if simulated > 0 { return "\(real) cerca + \(simulated) sim." }
        return "\(real) cerca"
    }

    private var hero: some View {
        let emergency = model.memory.emergencyActive
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FaroMark(size: 54, emergency: emergency)
                VStack(alignment: .leading, spacing: 3) {
                    Text(emergency ? "Modo emergencia" : "Todo tranquilo")
                        .font(.title2.weight(.bold))
                    Text(emergency
                         ? "Trabajo por ti sin internet, con los teléfonos cercanos."
                         : "Te cuido en segundo plano. Si se cae la red, me activo solo.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            HStack(spacing: 8) {
                StatusChip(
                    text: model.effectiveConnectivity == .online ? "Con internet" : "Sin internet",
                    systemImage: model.effectiveConnectivity == .online ? "wifi" : "wifi.slash"
                )
                StatusChip(
                    text: nearbyText,
                    systemImage: "antenna.radiowaves.left.and.right",
                    color: model.peerSession.connectedPeerNames.isEmpty && model.simulatedNeighborCount == 0 ? .white : FaroTheme.beam
                )
                if !model.memory.unsentOutbox.isEmpty {
                    StatusChip(text: "\(model.memory.unsentOutbox.count) por enviar", systemImage: "envelope.fill")
                }
            }

            if emergency {
                MeshRadarView(nodes: model.meshNodes)
            }

            Button {
                withAnimation(.snappy) { model.setEmergency(!emergency) }
            } label: {
                Label(emergency ? "Volver a modo normal" : "Activar modo emergencia",
                      systemImage: emergency ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(emergency ? .white.opacity(0.25) : FaroTheme.ember)

            if emergency {
                Text("Si hay una emergencia médica, llama al \(model.profile.country.emergencyNumber). Faro no reemplaza a los servicios de emergencia.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(FaroTheme.heroGradient(emergency: emergency))
        )
    }
}

private struct PendingCard: View {
    @EnvironmentObject private var model: AppModel
    let pending: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pending.title, systemImage: "hand.raised.fill")
                .font(.headline)
            Text(pending.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    withAnimation { model.approve(pending) }
                } label: {
                    Text("Sí, hazlo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    withAnimation { model.dismiss(pending) }
                } label: {
                    Text("Ahora no").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(need.resource.displayName, systemImage: need.resource.systemImage)
                    .font(.headline)
                Spacer()
                Text(iReceive ? "Recibes" : "Entregas")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(iReceive ? FaroTheme.safe : .orange)
            }
            if let terms = summary.negotiation.agreedTerms {
                Text("\(terms.quantity) \(need.unit) con \(other)")
                    .font(.title3.weight(.semibold))
                Label(terms.meetingPoint, systemImage: "mappin.and.ellipse")
                Label(terms.meetAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
            }
            if model.hasCompleted(summary) {
                Label("Marcaste la entrega como hecha.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(FaroTheme.safe)
            } else {
                Button("Ya se entregó") { model.complete(summary) }
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
        .faroCard(tint: FaroTheme.safe)
    }
}

private struct PreparednessCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let report = model.profile.preparedness
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(report.score) / 100)
                    .stroke(FaroTheme.beam, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(report.score)")
                    .font(.title3.weight(.bold))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text("Preparación de tu hogar")
                    .font(.headline)
                if report.gaps.isEmpty {
                    Text("Todo listo. Te recordaré revisar el agua y las baterías.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.gaps.prefix(3), id: \.self) { gap in
                        Label(gap, systemImage: "circle.dashed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .faroCard()
    }
}

private struct FamilyStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tu familia", systemImage: "person.2.fill")
                .font(.headline)
            ForEach(model.familyCheckIns) { checkIn in
                HStack {
                    Circle()
                        .fill(checkIn.status == .safe ? FaroTheme.safe : FaroTheme.ember)
                        .frame(width: 10, height: 10)
                    Text(checkIn.authorName).font(.subheadline.weight(.semibold))
                    Text(checkIn.status.displayName.lowercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(checkIn.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .faroCard(tint: FaroTheme.safe)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(entry.kind.color, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
