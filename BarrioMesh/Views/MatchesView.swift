import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
                VStack(spacing: 14) {
                    if model.matchSummaries.isEmpty {
                        ContentUnavailableView {
                            Label(t("Todavía no hay matches", "No matches yet"), systemImage: "arrow.left.arrow.right")
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
                    subtitle: t("Necesita \(summary.candidate.need.resource.count(summary.candidate.need.quantity))", "Needs \(summary.candidate.need.resource.count(summary.candidate.need.quantity))"),
                    color: .orange
                )
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                person(
                    title: summary.candidate.offer.authorName,
                    subtitle: t("Ofrece \(summary.candidate.offer.resource.count(summary.candidate.offer.quantity))", "Offers \(summary.candidate.offer.resource.count(summary.candidate.offer.quantity))"),
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
                    Label(t("Abrir en WhatsApp", "Open in WhatsApp"), systemImage: "arrow.up.forward.app")
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
                            Text(t("Agente de \(message.senderName): \(verb(for: message.kind))", "\(message.senderName)'s agent: \(verb(for: message.kind))"))
                                .font(.caption.weight(.semibold))
                            if let terms = message.terms, message.kind != .accept {
                                Text("\(terms.quantity) · \(terms.meetingPoint) · \(terms.meetAt.formatted(date: .omitted, time: .shortened))")
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
        case .propose: t("propone", "proposes")
        case .counter: t("contraoferta", "counters")
        case .accept: t("acepta", "accepts")
        case .decline: t("rechaza", "declines")
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

        return [
            t("🤝 Faro encontró una coincidencia", "🤝 Faro found a match"),
            "",
            need.resource.displayName,
            "• \(need.authorName) \(t("necesita", "needs")) \(need.resource.count(need.quantity))",
            "• \(offer.authorName) \(t("ofrece", "offers")) \(offer.resource.count(offer.quantity))",
            "• \(t("Zona", "Area")): \(need.area)",
            "• \(t("Estado", "Status")): \(summary.status.displayName)",
            "",
            t("Coordina en un lugar público, sin direcciones exactas.", "Meet somewhere public; no exact addresses.")
        ].joined(separator: "\n")
    }

    @ViewBuilder
    private var actionArea: some View {
        let isParticipant = summary.requiredPeers.contains(model.deviceID)

        if !isParticipant {
            Label(t("Este teléfono está retransmitiendo la coincidencia.", "This phone is relaying this match."), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch summary.status {
            case .suggested, .waiting:
                if summary.isAgentNegotiated {
                    Label(t("Los agentes están negociando. Si necesitan tu OK, aparece en Inicio.", "Agents are negotiating. If they need you, it shows on Home."), systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if model.hasApproved(summary) {
                    Label(t("Confirmado por ti; falta la otra persona.", "You confirmed; waiting for the other person."), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button(t("Confirmar", "Confirm")) { model.approve(summary) }
                            .buttonStyle(.borderedProminent)
                        Button(t("Rechazar", "Decline"), role: .destructive) { model.decline(summary) }
                            .buttonStyle(.bordered)
                    }
                }
            case .accepted:
                if model.hasCompleted(summary) {
                    Label(t("Marcado como entregado; falta la otra confirmación.", "Marked delivered; waiting for the other side."), systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(t("Marcar ayuda como entregada", "Mark as delivered")) { model.complete(summary) }
                        .buttonStyle(.borderedProminent)
                }
            case .completed:
                Label(t("Ambas personas confirmaron la entrega.", "Both confirmed the handoff."), systemImage: "checkmark.seal.fill")
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
