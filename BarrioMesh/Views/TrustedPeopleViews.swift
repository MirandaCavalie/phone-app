import SwiftUI

/// Rows for the Family tab: who your agent coordinates with, and their latest word.
struct TrustedPeopleSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            ForEach(model.memory.trusted.filter { $0.status != .revoked }) { person in
                NavigationLink {
                    TrustedPersonView(personID: person.agentID)
                } label: {
                    TrustedRow(person: person, update: model.memory.trustedUpdates[person.agentID])
                }
            }
            NavigationLink {
                NearbyAgentsView()
            } label: {
                Label(t("Agregar persona de confianza", "Add trusted person"), systemImage: "person.crop.circle.badge.checkmark")
            }
        } header: {
            Text(t("Personas de confianza", "Trusted people"))
        } footer: {
            Text(t("Sus agentes y el tuyo se coordinan directo, cifrado y sin internet.", "Their agent and yours coordinate directly, encrypted, without internet."))
        }
    }
}

private struct TrustedRow: View {
    let person: TrustedPerson
    let update: TrustedUpdate?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: person.status == .active ? "checkmark.shield.fill" : "hourglass")
                .font(.title3)
                .foregroundStyle(person.status == .active ? FaroTheme.safe : .orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        if let update {
            return "\(update.status?.displayName ?? t("Sin estado", "No status")) · \(update.sentAt.formatted(date: .omitted, time: .shortened))"
        }
        switch person.status {
        case .invited: return t("Invitación enviada", "Invitation sent")
        case .active: return t("Código \(person.pairingCode)", "Code \(person.pairingCode)")
        case .revoked: return t("Revocado", "Revoked")
        }
    }
}

/// What you share with one person, what they share with you, and their latest update.
struct TrustedPersonView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let personID: String

    var body: some View {
        if let person = model.memory.trusted.first(where: { $0.agentID == personID }) {
            Form {
                if person.status == .active {
                    Section {
                        LabeledContent(t("Código de emparejamiento", "Pairing code"), value: person.pairingCode)
                            .font(.body.monospacedDigit())
                    } footer: {
                        Text(t("Debe ser igual en su teléfono. Si no coincide, revoca.", "It must match on their phone. If not, revoke."))
                    }
                } else if person.status == .invited {
                    Section {
                        Label(t("Esperando que su agente acepte. Mantengan los teléfonos cerca.", "Waiting for their agent to accept. Keep the phones close."), systemImage: "hourglass")
                    }
                }

                if let update = model.memory.trustedUpdates[person.agentID] {
                    Section(t("Último aviso", "Latest update")) {
                        LabeledContent(t("Estado", "Status"), value: update.status?.displayName ?? "—")
                        LabeledContent(t("Zona", "Area"), value: update.area)
                        ForEach(update.household, id: \.name) { relative in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(relative.name) · \(relative.relation)").font(.subheadline.weight(.semibold))
                                if let location = relative.location { Text(location).font(.caption) }
                                if let medical = relative.medical { Text(medical).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        if !update.needs.isEmpty {
                            LabeledContent(t("Necesita", "Needs"), value: update.needs.joined(separator: ", "))
                        }
                        Text(update.sentAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(TrustScope.allCases) { scope in
                        Toggle(isOn: Binding(
                            get: { person.sharing.contains(scope) },
                            set: { on in
                                var scopes = person.sharing
                                if on { scopes.insert(scope) } else { scopes.remove(scope) }
                                model.setSharing(scopes, for: person)
                            }
                        )) {
                            Label(scope.displayName, systemImage: scope.systemImage)
                        }
                    }
                } header: {
                    Text(t("Lo que mi agente comparte con \(person.name)", "What my agent shares with \(person.name)"))
                } footer: {
                    Text(t("Solo en una emergencia, cifrado solo para su agente.", "Only in an emergency, encrypted for their agent only."))
                }

                if !person.theyShare.isEmpty {
                    Section(t("Lo que \(person.name) comparte contigo", "What \(person.name) shares with you")) {
                        ForEach(person.theyShare.sorted { $0.rawValue < $1.rawValue }) { scope in
                            Label(scope.displayName, systemImage: scope.systemImage)
                        }
                    }
                }

                Section {
                    Button(t("Dejar de confiar", "Stop trusting"), role: .destructive) {
                        model.revokeTrusted(person)
                        dismiss()
                    }
                }
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Agents nearby (seen on the mesh) that can be invited.
struct NearbyAgentsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if model.nearbyAgents.isEmpty {
                    Text(t("Aún no veo agentes cerca. Abran Faro en ambos teléfonos, juntos.", "No agents nearby yet. Open Faro on both phones, side by side."))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.nearbyAgents, id: \.id) { agent in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name).font(.subheadline.weight(.semibold))
                            Text(MeshSecurity.fingerprint(of: Data(agent.id.utf8))).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(t("Invitar", "Invite")) {
                            model.inviteTrusted(id: agent.id, name: agent.name)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } footer: {
                Text(t("Al aceptar, ambos teléfonos muestran el mismo código de 6 dígitos.", "When they accept, both phones show the same 6-digit code."))
            }
        }
        .navigationTitle(t("Agentes cercanos", "Nearby agents"))
    }
}
