import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        Form {
                Section {
                    ConnectionBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section(t("Este teléfono", "This phone")) {
                    LabeledContent("Nombre visible", value: model.profile.name)
                    LabeledContent("Identificador", value: String(model.deviceID.prefix(8)))
                        .font(.caption)
                    LabeledContent("Publicaciones conocidas", value: "\(model.meshState.posts.count)")
                    if let lastSyncAt = model.lastSyncAt {
                        LabeledContent("Última sincronización") {
                            Text(lastSyncAt, style: .relative)
                        }
                    }
                }

                Section(t("Teléfonos conectados", "Connected phones")) {
                    if model.peerSession.connectedPeerNames.isEmpty {
                        Text("Abre Faro en el otro iPhone y acepta el permiso de red local.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.peerSession.connectedPeerNames, id: \.self) { name in
                            Label(name, systemImage: "iphone.radiowaves.left.and.right")
                        }
                    }
                }

                Section(t("Privacidad", "Privacy")) {
                    Label(t("La sesión entre teléfonos está cifrada.", "The session between phones is encrypted."), systemImage: "lock.fill")
                    Label(t("Todo lo que publica este teléfono va firmado (Ed25519).", "Everything this phone posts is signed (Ed25519)."), systemImage: "signature")
                    Label(t("Los avisos familiares viajan cifrados de extremo a extremo.", "Family check-ins are end-to-end encrypted."), systemImage: "lock.shield.fill")
                    LabeledContent("Huella de este teléfono", value: model.identity.fingerprint)
                        .font(.caption.monospaced())
                    if model.rejectedItems > 0 {
                        Label(t("Descarté \(model.rejectedItems) elementos sin firma válida.", "Rejected \(model.rejectedItems) items without a valid signature."), systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                    }
                    Label(t("No se necesita cuenta, SIM ni servidor.", "No account, SIM or server needed."), systemImage: "cloud.slash.fill")
                    Label(t("Solo se comparten zonas aproximadas.", "Only approximate areas are shared."), systemImage: "location.slash.fill")
                }

                Section(t("Respaldo para la demo", "Demo fallback")) {
                    Button(t("Simular vecinos cercanos", "Simulate nearby neighbors")) {
                        model.startSimulatedNeighbors()
                    }
                    Text("Crea agentes ficticios marcados “(simulado)” si un segundo teléfono falla. No finge una conexión real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(t("Borrar datos locales", "Erase local data"), role: .destructive) {
                        confirmReset = true
                    }
                    Text("Si otro teléfono conserva publicaciones, puede volver a retransmitirlas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(t("Red local", "Local network"))
            .confirmationDialog(
                t("¿Borrar todas las publicaciones y coordinaciones de este teléfono?", "Erase all posts and handoffs on this phone?"),
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button(t("Borrar datos", "Erase data"), role: .destructive) { model.resetLocalData() }
                Button(t("Cancelar", "Cancel"), role: .cancel) {}
            }
    }
}
