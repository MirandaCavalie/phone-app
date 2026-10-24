import SwiftUI

/// A conversation with the agent. Questions are answered from what the agent knows
/// (on-device model with tools, or the local engine); needs and offers become drafts to review.
struct AskFaroView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private struct Turn: Identifiable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var draft: AgentDraft?
        var engine: AgentEngine?
        var actions: [ProposedAction] = []
        var searched = false
    }

    @State private var turns: [Turn] = []
    @State private var message = ""
    @State private var isThinking = false
    @State private var composing: AgentDraft?
    @State private var resolved: [UUID: String] = [:]
    @State private var orderToReview: SupplyOrder?
    @Environment(\.openURL) private var openURL
    @StateObject private var listener = SpeechListener()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        ForEach(turns) { turn in
                            bubble(turn).id(turn.id)
                        }
                        if isThinking {
                            ProgressView().padding(.leading, 8)
                        }
                    }
                    .padding()
                }
                .onChange(of: turns.count) {
                    if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle(t("Háblale a Faro", "Talk to Faro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Listo", "Done")) { dismiss() }
                }
            }
            .sheet(item: $composing) { draft in
                PostComposerView(kind: draft.kind, initialDraft: draft)
            }
            .sheet(item: Binding(get: { orderToReview.map(IdentifiedOrder.init) }, set: { orderToReview = $0?.order })) { wrapper in
                SupplyOrderView(order: wrapper.order)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FaroMark(size: 40)
                Text(t("Pregúntame o pídeme algo: tu familia, alertas, la mochila, tu agenda. Mantén presionado el micrófono para hablarme.",
                       "Ask me anything or ask me to do it: family, alerts, go-bag, your calendar. Hold the mic to talk."))
                    .font(.subheadline)
            }
            Label(model.onlineBrainReady
                  ? t("Con internet: Claude con búsqueda web. Sin internet: este iPhone y Bluetooth.", "Online: Claude with web search. Offline: this iPhone and Bluetooth.")
                  : t("Sin internet: funciono en este iPhone y por Bluetooth.", "Offline: running on this iPhone and over Bluetooth."),
                  systemImage: model.onlineBrainReady ? "cloud.fill" : "lock.iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { send(suggestion) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .faroCard()
    }

    private var suggestions: [String] {
        [
            t("¿Mi familia está bien?", "Is my family OK?"),
            t("¿Qué tengo acordado?", "What handoffs do I have?"),
            t("¿Qué me falta en el kit?", "What is missing from my kit?"),
            t("¿Quién está cerca?", "Who is nearby?"),
            t("Necesito 2 cargas de teléfono en \(model.profile.homeArea)", "I need 2 phone charges in \(model.profile.homeArea)")
        ]
    }

    @ViewBuilder
    private func bubble(_ turn: Turn) -> some View {
        if turn.fromUser {
            Text(turn.text)
                .padding(12)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(turn.text)
                if let draft = turn.draft {
                    if !draft.missingFields.isEmpty {
                        Label(t("Falta \(draft.missingFields.map(\.displayName).joined(separator: " y ")).", "Missing \(draft.missingFields.map(\.displayName).joined(separator: " and "))."), systemImage: "questionmark.bubble")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(draft.notices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button(t("Revisar y publicar", "Review and post")) { composing = draft }
                        .buttonStyle(.borderedProminent)
                }
                ForEach(turn.actions) { action in
                    actionCard(action)
                }
                if let engine = turn.engine {
                    Text(turn.searched ? "\(engine.displayName) · \(t("buscó en la web", "searched the web"))" : engine.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if listener.isListening {
                Label(listener.transcript.isEmpty ? t("Te escucho…", "Listening…") : listener.transcript, systemImage: "waveform")
                    .font(.subheadline)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let problem = listener.problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                micButton
                textInput
            }
        }
        .padding()
        .background(.bar)
        .onAppear { listener.configure(for: model.profile.country) }
    }

    /// Hold to talk, release to send.
    private var micButton: some View {
        Image(systemName: listener.isListening ? "mic.fill" : "mic")
            .font(.title2)
            .foregroundStyle(listener.isListening ? .white : Color.accentColor)
            .frame(width: 44, height: 44)
            .background(listener.isListening ? FaroTheme.ember : Color.accentColor.opacity(0.12), in: Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !listener.isListening else { return }
                        Task { await listener.start() }
                    }
                    .onEnded { _ in
                        let heard = listener.finish()
                        if !heard.isEmpty { send(heard, spoken: true) }
                    }
            )
            .accessibilityLabel(t("Mantén presionado para hablarle a Faro", "Hold to talk to Faro"))
            .accessibilityAddTraits(.isButton)
    }

    private var textInput: some View {
        HStack(spacing: 10) {
            TextField(t("Escríbele a Faro", "Message Faro"), text: $message, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { send(message) }
            Button {
                send(message)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
        }
    }

    private func send(_ text: String, spoken: Bool = false) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isThinking else { return }
        message = ""
        turns.append(Turn(fromUser: true, text: cleaned))
        isThinking = true

        Task {
            defer { isThinking = false }
            if model.onlineBrainReady {
                do {
                    let reply = try await model.onlineBrain.ask(cleaned, model: model)
                    turns.append(Turn(fromUser: false, text: reply.text, engine: .claude, actions: reply.actions, searched: reply.searched))
                    if spoken || model.memory.emergencyActive, model.speaksUpdates {
                        model.narrator.speak(reply.text, country: model.profile.country)
                    }
                    return
                } catch {
                    turns.append(Turn(fromUser: false, text: t("Sin conexión con Claude (\(error.localizedDescription)). Sigo en el teléfono.", "Couldn't reach Claude (\(error.localizedDescription)). Continuing on the phone.")))
                }
            }
            if let note = trustedNoteIntent(cleaned) {
                turns.append(Turn(fromUser: false, text: t("Puedo mandarlo cifrado por Bluetooth, sin internet.", "I can send it encrypted over Bluetooth, no internet needed."),
                                  engine: .localRules, actions: [note]))
            } else if Self.looksLikeRequest(cleaned) {
                let result = await PersonalAgentInterpreter.interpret(cleaned, emergencyNumber: model.profile.country.emergencyNumber)
                var draft = result.draft
                if draft.area.isEmpty { draft.area = model.profile.homeArea }
                turns.append(Turn(fromUser: false, text: draft.summary + t(" Revísalo antes de publicarlo.", " Review it before posting."), draft: draft, engine: result.engine))
            } else {
                let (answer, engine) = await AgentBrain.answer(cleaned, snapshot: model.snapshot)
                turns.append(Turn(fromUser: false, text: answer, engine: engine))
                // Asked by voice, answered by voice.
                if spoken || model.memory.emergencyActive, model.speaksUpdates {
                    model.narrator.speak(answer, country: model.profile.country)
                }
            }
        }
    }

    /// "Mensaje a Juan: estoy bien" / "Message Juan: I'm OK" → an offline note to a trusted person.
    private func trustedNoteIntent(_ text: String) -> ProposedAction? {
        let pattern = #"(?i)^\s*(?:mensaje|mensajea|dile|escribe|message|tell|text)\s+(?:a\s+|to\s+)?([^:,]+?)\s*[:,]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
        let name = String(text[nameRange])
        guard let person = model.memory.activeTrusted.first(where: { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }) else { return nil }
        let body = String(text[bodyRange])
        return ProposedAction(kind: .note(agentID: person.agentID, name: person.name, text: body), title: t("Mensaje a \(person.name)", "Message \(person.name)"), detail: body)
    }

    private func actionCard(_ action: ProposedAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(action.title).font(.subheadline.weight(.semibold))
            if !action.detail.isEmpty {
                Text(action.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if let outcome = resolved[action.id] {
                Label(outcome, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(FaroTheme.safe)
            } else {
                HStack {
                    Button(t("Confirmar", "Confirm")) {
                        if action.kind == .order {
                            orderToReview = SupplyOrder(gaps: GoBag.audit(model.profile.goBag, for: model.profile, now: Date()))
                        }
                        Task { resolved[action.id] = await model.execute(action) { openURL($0) } }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(t("No", "No")) { resolved[action.id] = t("Cancelado.", "Cancelled.") }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FaroTheme.beam.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Needs and offers become drafts; everything else is a question for the agent.
    static func looksLikeRequest(_ text: String) -> Bool {
        let lower = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        guard !lower.contains("?") else { return false }
        let verbs = ["necesito", "necesitamos", "busco", "me falta", "ofrezco", "puedo ofrecer", "puedo ayudar", "tengo", "comparto",
                     "i need", "we need", "looking for", "i can offer", "i can help", "i have", "we have"]
        return verbs.contains(where: lower.contains) && OfflineAgent.interpret(text).resource != nil
    }
}

extension AgentDraft: Identifiable {
    public var id: String { originalText + kind.rawValue }
}
