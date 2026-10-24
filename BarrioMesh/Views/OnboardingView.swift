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
                HStack {
                    Spacer()
                    LanguagePicker()
                        .frame(width: 120)
                }
                Spacer(minLength: 30)
                FaroMark(size: 88)
                Text("Faro")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                Text("Tu agente personal para cuando todo falla.")
                    .font(.title2.weight(.semibold))
                Text("Hoy te conoce. Si mañana tiembla y se cae la señal, avisa a tu familia, pide lo que tu hogar necesita y coordina con tus vecinos por Bluetooth, sin internet.")
                    .foregroundStyle(.white.opacity(0.8))
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("Funciona 100% en tu teléfono", "Runs 100% on your phone"), systemImage: "iphone")
                    Label(t("Sin cuentas, sin servidores, sin SIM", "No accounts, servers or SIM"), systemImage: "antenna.radiowaves.left.and.right.slash")
                    Label(t("Tú decides qué puede hacer solo", "You decide what it does alone"), systemImage: "checkmark.shield")
                }
                .font(.subheadline)
                .foregroundStyle(FaroTheme.beam)
            }
        case .basics:
            VStack(alignment: .leading, spacing: 16) {
                title(t("¿Cómo te llamas?", "What's your name?"), t("Así te verán tus vecinos y tu familia.", "How neighbors and family will see you."))
                field(t("Tu nombre", "Your name"), text: $draft.name)
                Picker(t("País", "Country"), selection: $draft.country) {
                    ForEach(Country.allCases) { country in
                        Text("\(country.flag) \(country.displayName)").tag(country)
                    }
                }
                .pickerStyle(.menu)
                .tint(FaroTheme.beam)
                title(t("¿En qué zona vives?", "Where do you live?"), t("Solo el barrio, nunca tu dirección.", "Just the neighborhood, never your address."))
                field(t("Ej.: Chapinero, Chacao, El Poblado", "e.g. Miraflores, Chapinero, El Poblado"), text: $draft.homeArea)
                title(t("Un punto de encuentro público", "A public meeting point"), t("Faro lo propone para las entregas con vecinos.", "Faro suggests it for handoffs."))
                field(t("Ej.: Parque de la 93, la iglesia, la panadería", "e.g. Parque Kennedy, the church, the bakery"), text: $draft.meetingPoint)
            }
        case .household:
            VStack(alignment: .leading, spacing: 16) {
                title(t("Cuéntame de tu hogar", "Tell me about your home"), t("Con quién vives, qué tienes guardado, qué necesitarían. Lo uso para actuar por ti en una emergencia.", "Who you live with, what you have, what you'd need."))
                TextEditor(text: $householdText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(10)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                Button(t("Usar un ejemplo", "Use an example")) {
                    householdText = t("Vivo con mi mamá que usa insulina. Tengo 12 botellas de agua, una batería externa y carro. Soy enfermera.", "I live with my mom who uses insulin. I have 12 bottles of water, a power bank and a car. I am a nurse.")
                }
                .font(.caption)
                .tint(FaroTheme.beam)

                Button {
                    Task { await learn() }
                } label: {
                    if isThinking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(t("Entender mi hogar", "Understand my home"), systemImage: "sparkles").frame(maxWidth: .infinity)
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
                title(t("Tu círculo familiar", "Your family circle"), t("Escriban el mismo código en sus teléfonos. Sus “estoy bien” llegarán saltando entre teléfonos cercanos.", "Use the same code on each phone. Check-ins hop between nearby phones."))
                field(t("Código de familia", "Family code"), text: $draft.familyCircleCode)
                    .textInputAutocapitalization(.never)
                Button(t("Generar un código seguro", "Generate a secure code")) { draft.familyCircleCode = FamilyCircle.suggestCode() }
                    .font(.subheadline.weight(.semibold))
                    .tint(FaroTheme.beam)
                title(t("Alguien a quien avisar", "Someone to notify"), t("Cuando vuelva la señal, te dejo el mensaje listo para enviar.", "When signal returns, the message is ready to send."))
                field(t("Nombre", "Name"), text: $contactName)
                field(t("Teléfono con código de país", "Phone with country code"), text: $contactPhone)
                    .keyboardType(.phonePad)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 14) {
                title(t("¿Qué puedo hacer solo?", "What can I do on my own?"), t("Si se cae internet, actúo dentro de estos límites y te pregunto por todo lo demás.", "In an emergency I act within these limits and ask about everything else."))
                toggle(t("Activar modo emergencia al perder internet", "Start emergency mode when offline"), $policy.activateOnOutage)
                toggle(t("Activar al sentir un sismo", "Start when the phone feels a quake"), $policy.activateOnShaking)
                toggle(t("Activar con alertas oficiales de sismo o tsunami", "Start on official quake or tsunami alerts"), $policy.activateOnOfficialAlert)
                toggle(t("Avisar a mi familia que estoy bien", "Tell my family I'm OK"), $policy.autoCheckIn)
                toggle(t("Pedir lo que mi hogar necesita", "Request what my household needs"), $policy.autoPublishNeeds)
                toggle(t("Ofrecer lo que nos sobra", "Offer what we can spare"), $policy.autoPublishOffers)
                toggle(t("Aceptar ayuda de vecinos", "Accept help from neighbors"), $policy.autoAcceptIncomingHelp)
                Stepper(t("Comprometer hasta \(policy.autoGiveLimit) unidades por entrega", "Give up to \(policy.autoGiveLimit) per handoff without asking"), value: $policy.autoGiveLimit, in: 0...10)
                Label(t("Medicinas y primeros auxilios siempre te los pregunto.", "I always ask about medicine and first aid."), systemImage: "cross.case.fill")
                    .font(.caption)
                    .foregroundStyle(FaroTheme.beam)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(t("Atrás", "Back")) { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome } }
                    .tint(.white)
            }
            Spacer()
            Button {
                advance()
            } label: {
                Text(step == .permissions ? t("Listo, cuídame", "Done, watch over me") : t("Continuar", "Continue"))
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
        learned = result.learned.isEmpty ? [t("No encontré detalles todavía. Puedes agregarlos en Perfil.", "No details yet. Add them in Profile.")] : result.learned
        engine = usedEngine
    }

    private func finish() {
        if !contactName.isEmpty, contactPhone.filter(\.isNumber).count >= 7 {
            draft.familyContacts.append(FamilyContact(name: contactName, phone: contactPhone))
        }
        if draft.meetingPoint.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.meetingPoint = t("Parque principal de \(draft.homeArea)", "\(draft.homeArea) main park")
        }
        model.policy = policy
        model.profile = draft
        HazardMonitor.requestNotificationPermission()
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
