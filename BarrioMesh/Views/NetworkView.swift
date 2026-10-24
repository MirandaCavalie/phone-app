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

                Section("Este teléfono") {
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

                Section("Teléfonos conectados") {
                    if model.peerSession.connectedPeerNames.isEmpty {
                        Text("Abre Faro en el otro iPhone y acepta el permiso de red local.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.peerSession.connectedPeerNames, id: \.self) { name in
                            Label(name, systemImage: "iphone.radiowaves.left.and.right")
                        }
                    }
                }

                Section("Privacidad") {
                    Label("La sesión entre teléfonos está cifrada.", systemImage: "lock.fill")
                    Label("Todo lo que publica este teléfono va firmado (Ed25519).", systemImage: "signature")
                    Label("Los avisos familiares viajan cifrados de extremo a extremo.", systemImage: "lock.shield.fill")
                    LabeledContent("Huella de este teléfono", value: model.identity.fingerprint)
                        .font(.caption.monospaced())
                    if model.rejectedItems > 0 {
                        Label("Descarté \(model.rejectedItems) elementos sin firma válida.", systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                    }
                    Label("No se necesita cuenta, SIM ni servidor.", systemImage: "cloud.slash.fill")
                    Label("Solo se comparten zonas aproximadas.", systemImage: "location.slash.fill")
                }

                Section("Respaldo para la demo") {
                    Button("Simular vecinos cercanos") {
                        model.startSimulatedNeighbors()
                    }
                    Text("Crea agentes ficticios marcados “(simulado)” si un segundo teléfono falla. No finge una conexión real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Borrar datos locales", role: .destructive) {
                        confirmReset = true
                    }
                    Text("Si otro teléfono conserva publicaciones, puede volver a retransmitirlas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Red local")
            .confirmationDialog(
                "¿Borrar todas las publicaciones y coordinaciones de este teléfono?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Borrar datos", role: .destructive) { model.resetLocalData() }
                Button("Cancelar", role: .cancel) {}
            }
    }
}
