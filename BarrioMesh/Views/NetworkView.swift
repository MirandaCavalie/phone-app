import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ConnectionBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Este teléfono") {
                    TextField("Nombre visible", text: $model.displayName)
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
                        Text("Abrí Barrio Mesh en el segundo iPhone y aceptá el permiso de red local.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.peerSession.connectedPeerNames, id: \.self) { name in
                            Label(name, systemImage: "iphone.radiowaves.left.and.right")
                        }
                    }
                }

                Section("Privacidad") {
                    Label("La sesión entre teléfonos está cifrada.", systemImage: "lock.fill")
                    Label("No se necesita cuenta, SIM ni servidor.", systemImage: "cloud.slash.fill")
                    Label("Solo compartí zonas aproximadas.", systemImage: "location.slash.fill")
                }

                Section("Respaldo para la demo") {
                    Button("Cargar un caso de prueba local") {
                        model.loadDemoData()
                    }
                    Text("Crea una necesidad y una oferta ficticias para mostrar la interfaz si un segundo teléfono falla.")
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
}
