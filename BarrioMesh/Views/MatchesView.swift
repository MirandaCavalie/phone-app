import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
                VStack(spacing: 14) {
                    if model.matchSummaries.isEmpty {
                        ContentUnavailableView {
                            Label("Todavía no hay matches", systemImage: "arrow.left.arrow.right")
                        } description: {
                            Text("Cuando una necesidad y una oferta sean compatibles, los agentes negocian y aparecen aquí.")
                        }
                        .frame(minHeight: 420)
                    } else {
                        ForEach(model.matchSummaries) { summary in
                            MatchCard(summary: summary)
                        }
                    }
                }
                .padding()
            }
    }
}

private struct MatchCard: View {
    @EnvironmentObject private var model: AppModel
    let summary: AppModel.MatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(summary.candidate.need.resource.displayName, systemImage: summary.candidate.need.resource.systemImage)
                    .font(.headline)
                Spacer()
                statusLabel
            }

            HStack(spacing: 10) {
                person(
                    title: summary.candidate.need.authorName,
                    subtitle: "Necesita \(summary.candidate.need.quantity) \(summary.candidate.need.unit)",
                    color: .orange
                )
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                person(
                    title: summary.candidate.offer.authorName,
                    subtitle: "Ofrece \(summary.candidate.offer.quantity) \(summary.candidate.offer.unit)",
                    color: .green
                )
            }

            Label(summary.candidate.reason, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)

            negotiationTrail

            actionArea

            if let whatsAppURL {
                Link(destination: whatsAppURL) {
                    Label("Abrir en WhatsApp", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .accessibilityHint("Prepara el mensaje; tú eliges el contacto y confirmas el envío.")

                Text("Nada se envía automáticamente. WhatsApp necesita conexión a internet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var negotiationTrail: some View {
        if summary.isAgentNegotiated {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.negotiation.messages) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: message.kind))
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Agente de \(message.senderName): \(verb(for: message.kind))")
                                .font(.caption.weight(.semibold))
                            if let terms = message.terms, message.kind != .accept {
                                Text("\(terms.quantity) en \(terms.meetingPoint), \(terms.meetAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func icon(for kind: AgentMessage.Kind) -> String {
        switch kind {
        case .propose: "arrow.up.right.circle.fill"
        case .counter: "arrow.triangle.2.circlepath.circle.fill"
        case .accept: "checkmark.circle.fill"
        case .decline: "xmark.circle.fill"
        }
    }

    private func verb(for kind: AgentMessage.Kind) -> String {
        switch kind {
        case .propose: "propone"
        case .counter: "contraoferta"
        case .accept: "acepta"
        case .decline: "rechaza"
        }
    }

    private var statusLabel: some View {
        Text(summary.status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch summary.status {
        case .suggested: .accentColor
        case .waiting: .orange
        case .accepted: .green
        case .declined: .red
        case .completed: .secondary
        }
    }

    private var whatsAppURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "text", value: shareMessage)]
        return components.url
    }

    private var shareMessage: String {
        let need = summary.candidate.need
        let offer = summary.candidate.offer

        return """
        🤝 Faro encontró una coincidencia

        \(need.resource.displayName)
        • \(need.authorName) necesita \(need.quantity) \(need.unit)
        • \(offer.authorName) puede ofrecer \(offer.quantity) \(offer.unit)
        • Zona aproximada: \(need.area)
        • Estado: \(summary.status.displayName)

        Coordina un punto público y no compartas direcciones exactas hasta confirmar el encuentro.
        """
    }

    @ViewBuilder
    private var actionArea: some View {
        let isParticipant = summary.requiredPeers.contains(model.deviceID)

        if !isParticipant {
            Label("Este teléfono está retransmitiendo la coincidencia.", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch summary.status {
            case .suggested, .waiting:
                if summary.isAgentNegotiated {
                    Label("Los agentes están negociando. Si necesitan tu OK, aparece en Inicio.", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if model.hasApproved(summary) {
                    Label("Confirmado por ti; falta la otra persona.", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Confirmar") { model.approve(summary) }
                            .buttonStyle(.borderedProminent)
                        Button("Rechazar", role: .destructive) { model.decline(summary) }
                            .buttonStyle(.bordered)
                    }
                }
            case .accepted:
                if model.hasCompleted(summary) {
                    Label("Marcado como entregado; falta la otra confirmación.", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Marcar ayuda como entregada") { model.complete(summary) }
                        .buttonStyle(.borderedProminent)
                }
            case .completed:
                Label("Ambas personas confirmaron la entrega.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .declined:
                EmptyView()
            }
        }
    }

    private func person(title: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
