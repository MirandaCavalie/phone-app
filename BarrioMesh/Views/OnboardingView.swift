import SwiftUI

/// First run: the agent gets to know its person, calmly, before anything goes wrong.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    private enum Step: Int, CaseIterable {
        case welcome, basics, household, family, permissions
    }

    @State private var step: Step = .welcome
    @State private var draft = AgentProfile()
    @State private var policy = AgentPolicy()
    @State private var householdText = ""
    @State private var learned: [String] = []
    @State private var engine: AgentEngine?
    @State private var isThinking = false
    @State private var contactName = ""
    @State private var contactPhone = ""

    var body: some View {
        ZStack {
            FaroTheme.heroGradient(emergency: false).ignoresSafeArea()

            VStack(spacing: 0) {
                if step != .welcome {
                    ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                        .tint(FaroTheme.beam)
                        .padding()
                }
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 60)
                FaroMark(size: 88)
                Text("Faro")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                Text("Tu agente personal para cuando todo falla.")
                    .font(.title2.weight(.semibold))
                Text("Hoy te conoce. Si mañana tiembla y se cae la señal, avisa a tu familia, pide lo que tu hogar necesita y coordina con tus vecinos por Bluetooth, sin internet.")
                    .foregroundStyle(.white.opacity(0.8))
                VStack(alignment: .leading, spacing: 10) {
                    Label("Funciona 100% en tu teléfono", systemImage: "iphone")
                    Label("Sin cuentas, sin servidores, sin SIM", systemImage: "antenna.radiowaves.left.and.right.slash")
                    Label("Tú decides qué puede hacer solo", systemImage: "checkmark.shield")
                }
                .font(.subheadline)
                .foregroundStyle(FaroTheme.beam)
            }
        case .basics:
            VStack(alignment: .leading, spacing: 16) {
                title("¿Cómo te llamas?", "Así te verán tus vecinos y tu familia.")
                field("Tu nombre", text: $draft.name)
                Picker("País", selection: $draft.country) {
                    ForEach(Country.allCases) { country in
                        Text("\(country.flag) \(country.displayName)").tag(country)
                    }
                }
                .pickerStyle(.menu)
                .tint(FaroTheme.beam)
                title("¿En qué zona vives?", "Solo el barrio, nunca tu dirección.")
                field("Ej.: Chapinero, Chacao, El Poblado", text: $draft.homeArea)
                title("Un punto de encuentro público", "Faro lo propone para las entregas con vecinos.")
                field("Ej.: Parque de la 93, la iglesia, la panadería", text: $draft.meetingPoint)
            }
        case .household:
            VStack(alignment: .leading, spacing: 16) {
                title("Cuéntame de tu hogar", "Con quién vives, qué tienes guardado, qué necesitarían. Lo uso para actuar por ti en una emergencia.")
                TextEditor(text: $householdText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(10)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                Button("Usar un ejemplo") {
                    householdText = "Vivo con mi mamá que usa insulina. Tengo 12 botellas de agua, una batería externa y carro. Soy enfermera."
                }
                .font(.caption)
                .tint(FaroTheme.beam)

                Button {
                    Task { await learn() }
                } label: {
                    if isThinking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Entender mi hogar", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(FaroTheme.beam)
                .foregroundStyle(FaroTheme.night)
                .disabled(householdText.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)

                if !learned.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Esto aprendí").font(.headline)
                        ForEach(learned, id: \.self) { line in
                            Label(line, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                        if let engine {
                            Text(engine.displayName).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Text("Puedes corregirlo después en Perfil.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        case .family:
            VStack(alignment: .leading, spacing: 16) {
                title("Tu círculo familiar", "Escriban el mismo código en sus teléfonos. Sus “estoy bien” llegarán saltando entre teléfonos cercanos.")
                field("Código de familia (ej.: casa-rodriguez)", text: $draft.familyCircleCode)
                    .textInputAutocapitalization(.never)
                title("Alguien a quien avisar", "Cuando vuelva la señal, te dejo el mensaje listo para enviar.")
                field("Nombre", text: $contactName)
                field("Teléfono con código de país", text: $contactPhone)
                    .keyboardType(.phonePad)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 14) {
                title("¿Qué puedo hacer solo?", "Si se cae internet, actúo dentro de estos límites y te pregunto por todo lo demás.")
                toggle("Activar modo emergencia al perder internet", $policy.activateOnOutage)
                toggle("Activar al sentir un sismo", $policy.activateOnShaking)
                toggle("Avisar a mi familia que estoy bien", $policy.autoCheckIn)
                toggle("Pedir lo que mi hogar necesita", $policy.autoPublishNeeds)
                toggle("Ofrecer lo que nos sobra", $policy.autoPublishOffers)
                toggle("Aceptar ayuda de vecinos", $policy.autoAcceptIncomingHelp)
                Stepper("Comprometer hasta \(policy.autoGiveLimit) unidades por entrega", value: $policy.autoGiveLimit, in: 0...10)
                Label("Medicinas y primeros auxilios siempre te los pregunto.", systemImage: "cross.case.fill")
                    .font(.caption)
                    .foregroundStyle(FaroTheme.beam)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Atrás") { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome } }
                    .tint(.white)
            }
            Spacer()
            Button {
                advance()
            } label: {
                Text(step == .permissions ? "Listo, cuídame" : "Continuar")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FaroTheme.beam)
            .foregroundStyle(FaroTheme.night)
            .disabled(!canAdvance)
        }
        .padding(24)
    }

    private var canAdvance: Bool {
        switch step {
        case .basics:
            !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !draft.homeArea.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            true
        }
    }

    private func advance() {
        if step == .household, learned.isEmpty, !householdText.isEmpty {
            Task {
                await learn()
                withAnimation { step = .family }
            }
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation { step = next }
    }

    private func learn() async {
        isThinking = true
        defer { isThinking = false }
        var base = draft
        base.household = []
        base.supplies = []
        base.standingNeeds = []
        let (result, usedEngine) = await AgentBrain.learnProfile(from: householdText, base: base)
        draft.household = result.profile.household
        draft.supplies = result.profile.supplies
        draft.standingNeeds = result.profile.standingNeeds
        learned = result.learned.isEmpty ? ["No encontré detalles todavía. Puedes agregarlos en Perfil."] : result.learned
        engine = usedEngine
    }

    private func finish() {
        if !contactName.isEmpty, contactPhone.filter(\.isNumber).count >= 7 {
            draft.familyContacts.append(FamilyContact(name: contactName, phone: contactPhone))
        }
        if draft.meetingPoint.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.meetingPoint = "Parque principal de \(draft.homeArea)"
        }
        model.policy = policy
        model.profile = draft
    }

    private func title(_ text: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.title2.weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 6)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(12)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggle(_ label: String, _ value: Binding<Bool>) -> some View {
        Toggle(label, isOn: value)
            .tint(FaroTheme.beam)
            .font(.subheadline)
    }
}
