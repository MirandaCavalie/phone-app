import SwiftUI

struct PostComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let kind: PostKind

    @State private var resource: ResourceKind = .water
    @State private var quantity = 1
    @State private var unit = ResourceKind.water.defaultUnit
    @State private var urgency: Urgency = .normal
    @State private var area = ""
    @State private var note = ""
    @State private var expiryHours = 4

    init(kind: PostKind, initialDraft: AgentDraft? = nil) {
        self.kind = kind
        let initialResource = initialDraft?.resource ?? .water
        _resource = State(initialValue: initialResource)
        _quantity = State(initialValue: initialDraft?.quantity ?? 1)
        _unit = State(initialValue: initialDraft?.unit ?? initialResource.defaultUnit)
        _urgency = State(initialValue: initialDraft?.urgency ?? .normal)
        _area = State(initialValue: initialDraft?.area ?? "")
        _note = State(initialValue: initialDraft?.note ?? "")
        _expiryHours = State(initialValue: initialDraft?.urgency == .urgent ? 1 : 4)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("Recurso", "Resource")) {
                    Picker(t("Categoría", "Category"), selection: $resource) {
                        ForEach(ResourceKind.allCases) { resource in
                            Label(resource.displayName, systemImage: resource.systemImage)
                                .tag(resource)
                        }
                    }

                    Stepper(t("Cantidad: \(quantity)", "Quantity: \(quantity)"), value: $quantity, in: 1...99)
                    TextField(t("Unidad", "Unit"), text: $unit)
                }

                Section(t("Ubicación y prioridad", "Area and priority")) {
                    TextField(t("Zona aproximada, por ejemplo Mission", "Approximate area, e.g. Miraflores"), text: $area)
                    Picker(t("Prioridad", "Priority"), selection: $urgency) {
                        ForEach(Urgency.allCases) { urgency in
                            Text(urgency.displayName).tag(urgency)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(t("Vence en", "Expires in"), selection: $expiryHours) {
                        Text("1 hora").tag(1)
                        Text("4 horas").tag(4)
                        Text("12 horas").tag(12)
                        Text("24 horas").tag(24)
                    }
                }

                Section(t("Detalle opcional", "Optional detail")) {
                    TextField(t("Información útil, sin datos sensibles", "Useful info, nothing sensitive"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("La zona aproximada circula por la red. No compartas una dirección exacta hasta confirmar un encuentro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancelar", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Publicar", "Post")) {
                        model.addPost(
                            kind: kind,
                            resource: resource,
                            quantity: quantity,
                            unit: unit,
                            urgency: urgency,
                            area: area,
                            note: note,
                            expiresIn: TimeInterval(expiryHours * 3_600)
                        )
                        dismiss()
                    }
                    .disabled(area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: resource) { _, newValue in
                unit = newValue.defaultUnit
            }
        }
    }
}
