import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.matchSummaries.isEmpty {
                        ContentUnavailableView {
                            Label("Todavía no hay matches", systemImage: "arrow.left.arrow.right")
                        } description: {
                            Text("Cuando una necesidad y una oferta sean compatibles aparecerán acá.")
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coordinación")
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

            actionArea
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var statusLabel: some View {
        Text(summary.status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch summary.status {
        case .suggested: .indigo
        case .waiting: .orange
        case .accepted: .green
        case .declined: .red
        case .completed: .secondary
        }
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
                if model.hasApproved(summary) {
                    Label("Confirmado por vos; falta la otra persona.", systemImage: "clock")
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
