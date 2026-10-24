import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LanguagePicker()
                }

                Section(t("Tú", "You")) {
                    TextField(t("Nombre", "Name"), text: $model.profile.name)
                    Picker(t("País", "Country"), selection: $model.profile.country) {
                        ForEach(Country.allCases) { country in
                            Text("\(country.flag) \(country.displayName)").tag(country)
                        }
                    }
                    TextField(t("Zona aproximada", "Approximate area"), text: $model.profile.homeArea)
                    TextField(t("Punto de encuentro público", "Public meeting point"), text: $model.profile.meetingPoint)
                    LabeledContent("Emergencias", value: model.profile.country.emergencyNumber)
                    LabeledContent("Alertas sísmicas cerca de", value: model.profile.approximateLocation.label)
                }

                Section {
                    ForEach($model.profile.supplies) { $supply in
                        VStack(alignment: .leading) {
                            Label(supply.resource.displayName, systemImage: supply.resource.systemImage)
                            Stepper(t("Tienes \(supply.quantity) \(supply.resource.defaultUnit)", "You have \(supply.resource.count(supply.quantity))"), value: $supply.quantity, in: 0...99)
                            Stepper(t("Reserva del hogar: \(supply.reserve)", "Household reserve: \(supply.reserve)"), value: $supply.reserve, in: 0...99)
                            Text("Faro puede compartir \(supply.shareable).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { model.profile.supplies.remove(atOffsets: $0) }
                    Menu(t("Agregar recurso", "Add supply")) {
                        ForEach(ResourceKind.allCases) { resource in
                            Button(resource.displayName) {
                                model.profile.supplies.append(Supply(resource: resource, quantity: 1))
                            }
                        }
                    }
                } header: {
                    Text("Lo que tienes")
                }

                Section(t("Lo que necesitarías", "What you would need")) {
                    ForEach($model.profile.standingNeeds) { $need in
                        VStack(alignment: .leading) {
                            Label(need.resource.displayName, systemImage: need.resource.systemImage)
                            Stepper(t("Cantidad: \(need.quantity)", "Quantity: \(need.quantity)"), value: $need.quantity, in: 1...99)
                            Picker(t("Prioridad", "Priority"), selection: $need.urgency) {
                                ForEach(Urgency.allCases) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                    .onDelete { model.profile.standingNeeds.remove(atOffsets: $0) }
                    Menu(t("Agregar necesidad", "Add need")) {
                        ForEach(ResourceKind.allCases) { resource in
                            Button(resource.displayName) {
                                model.profile.standingNeeds.append(StandingNeed(resource: resource))
                            }
                        }
                    }
                }

                Section {
                    Toggle(t("Activar modo emergencia al perder internet", "Start emergency mode when offline"), isOn: $model.policy.activateOnOutage)
                    Toggle(t("Activar al sentir un sismo", "Start when the phone feels a quake"), isOn: $model.policy.activateOnShaking)
                    Toggle(t("Activar con alertas oficiales (USGS, EMSC, GDACS, NOAA)", "Start on official alerts (USGS, EMSC, GDACS, NOAA)"), isOn: $model.policy.activateOnOfficialAlert)
                    Toggle(t("Avisar a mi familia que estoy bien", "Tell my family I'm OK"), isOn: $model.policy.autoCheckIn)
                    Toggle(t("Pedir lo que mi hogar necesita", "Request what my household needs"), isOn: $model.policy.autoPublishNeeds)
                    Toggle(t("Ofrecer lo que nos sobra", "Offer what we can spare"), isOn: $model.policy.autoPublishOffers)
                    Toggle(t("Aceptar ayuda de vecinos", "Accept help from neighbors"), isOn: $model.policy.autoAcceptIncomingHelp)
                    Stepper(t("Dar hasta \(model.policy.autoGiveLimit) sin preguntar", "Give up to \(model.policy.autoGiveLimit) without asking"), value: $model.policy.autoGiveLimit, in: 0...10)
                    Toggle(t("Leer en voz alta lo importante en una emergencia", "Read key updates aloud"), isOn: $model.speaksUpdates)
                } header: {
                    Text("Lo que Faro puede hacer solo")
                } footer: {
                    Text("Medicinas y primeros auxilios siempre requieren tu aprobación.")
                }

                Section(t("Red y demostración", "Network and demo")) {
                    NavigationLink(t("Red local", "Local network")) { NetworkView() }
                    Toggle(t("Simular corte de internet", "Simulate internet outage"), isOn: $model.simulateOutage)
                    Button(t("Simular sismo", "Simulate quake")) { model.simulateQuake() }
                    Button(t("Simular alerta oficial (USGS)", "Simulate official alert (USGS)")) { model.simulateOfficialAlert() }
                    Button(t("Simular vecinos cercanos", "Simulate nearby neighbors")) { model.startSimulatedNeighbors() }
                    Text("Crea agentes ficticios marcados “(simulado)” para mostrar la negociación con un solo teléfono.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(t("Borrar todo y empezar de nuevo", "Erase everything and start over"), role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle(t("Perfil", "Profile"))
            .confirmationDialog(t("¿Borrar tu perfil, la memoria del agente y los datos de la red en este teléfono?", "Erase your profile, the agent memory and network data on this phone?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(t("Borrar todo", "Erase everything"), role: .destructive) { model.resetEverything() }
                Button(t("Cancelar", "Cancel"), role: .cancel) {}
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
            Label(t("Depende de \(resource.displayName.lowercased())", "Relies on \(resource.displayName.lowercased())"), systemImage: resource.systemImage)
                .font(.caption)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
    }
}
