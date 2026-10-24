import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tú") {
                    TextField("Nombre", text: $model.profile.name)
                    Picker("País", selection: $model.profile.country) {
                        ForEach(Country.allCases) { country in
                            Text("\(country.flag) \(country.displayName)").tag(country)
                        }
                    }
                    TextField("Zona aproximada", text: $model.profile.homeArea)
                    TextField("Punto de encuentro público", text: $model.profile.meetingPoint)
                    LabeledContent("Emergencias", value: model.profile.country.emergencyNumber)
                }

                Section {
                    ForEach($model.profile.household) { $member in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Nombre", text: $member.name)
                                Text(member.relation).foregroundStyle(.secondary)
                            }
                            HStack {
                                dependencyToggle(.medicine, member: $member)
                                dependencyToggle(.power, member: $member)
                            }
                        }
                    }
                    .onDelete { model.profile.household.remove(atOffsets: $0) }
                    Button("Agregar persona") {
                        model.profile.household.append(HouseholdMember(name: "Familiar", relation: "familiar"))
                    }
                } header: {
                    Text("Tu hogar")
                } footer: {
                    Text("Si alguien depende de medicina o electricidad y no hay reserva, Faro lo pide primero.")
                }

                Section {
                    ForEach($model.profile.supplies) { $supply in
                        VStack(alignment: .leading) {
                            Label(supply.resource.displayName, systemImage: supply.resource.systemImage)
                            Stepper("Tienes \(supply.quantity) \(supply.resource.defaultUnit)", value: $supply.quantity, in: 0...99)
                            Stepper("Reserva del hogar: \(supply.reserve)", value: $supply.reserve, in: 0...99)
                            Text("Faro puede compartir \(supply.shareable).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { model.profile.supplies.remove(atOffsets: $0) }
                    Menu("Agregar recurso") {
                        ForEach(ResourceKind.allCases) { resource in
                            Button(resource.displayName) {
                                model.profile.supplies.append(Supply(resource: resource, quantity: 1))
                            }
                        }
                    }
                } header: {
                    Text("Lo que tienes")
                }

                Section("Lo que necesitarías") {
                    ForEach($model.profile.standingNeeds) { $need in
                        VStack(alignment: .leading) {
                            Label(need.resource.displayName, systemImage: need.resource.systemImage)
                            Stepper("Cantidad: \(need.quantity)", value: $need.quantity, in: 1...99)
                            Picker("Prioridad", selection: $need.urgency) {
                                ForEach(Urgency.allCases) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                    .onDelete { model.profile.standingNeeds.remove(atOffsets: $0) }
                    Menu("Agregar necesidad") {
                        ForEach(ResourceKind.allCases) { resource in
                            Button(resource.displayName) {
                                model.profile.standingNeeds.append(StandingNeed(resource: resource))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Activar modo emergencia al perder internet", isOn: $model.policy.activateOnOutage)
                    Toggle("Avisar a mi familia que estoy bien", isOn: $model.policy.autoCheckIn)
                    Toggle("Pedir lo que mi hogar necesita", isOn: $model.policy.autoPublishNeeds)
                    Toggle("Ofrecer lo que nos sobra", isOn: $model.policy.autoPublishOffers)
                    Toggle("Aceptar ayuda de vecinos", isOn: $model.policy.autoAcceptIncomingHelp)
                    Stepper("Dar hasta \(model.policy.autoGiveLimit) sin preguntar", value: $model.policy.autoGiveLimit, in: 0...10)
                } header: {
                    Text("Lo que Faro puede hacer solo")
                } footer: {
                    Text("Medicinas y primeros auxilios siempre requieren tu aprobación.")
                }

                Section("Red y demostración") {
                    NavigationLink("Red local") { NetworkView() }
                    Toggle("Simular corte de internet", isOn: $model.simulateOutage)
                    Button("Simular vecinos cercanos") { model.startSimulatedNeighbors() }
                    Text("Crea agentes ficticios marcados “(simulado)” para mostrar la negociación con un solo teléfono.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Borrar todo y empezar de nuevo", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Perfil")
            .confirmationDialog("¿Borrar tu perfil, la memoria del agente y los datos de la red en este teléfono?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { model.resetEverything() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private func dependencyToggle(_ resource: ResourceKind, member: Binding<HouseholdMember>) -> some View {
        let isOn = Binding(
            get: { member.wrappedValue.dependsOn.contains(resource) },
            set: { on in
                if on { member.wrappedValue.dependsOn.append(resource) }
                else { member.wrappedValue.dependsOn.removeAll { $0 == resource } }
            }
        )
        return Toggle(isOn: isOn) {
            Label("Depende de \(resource.displayName.lowercased())", systemImage: resource.systemImage)
                .font(.caption)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
    }
}
