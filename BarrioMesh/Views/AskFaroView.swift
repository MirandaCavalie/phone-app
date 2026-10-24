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
    }

    @State private var turns: [Turn] = []
    @State private var message = ""
    @State private var isThinking = false
    @State private var composing: AgentDraft?

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
            .navigationTitle("Háblale a Faro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(item: $composing) { draft in
                PostComposerView(kind: draft.kind, initialDraft: draft)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FaroMark(size: 40)
                Text("Pregúntame por tu familia, tus encuentros o tu kit. También puedes pedir u ofrecer ayuda.")
                    .font(.subheadline)
            }
            Label("Todo se procesa en este iPhone. Sin internet, sin API.", systemImage: "lock.iphone")
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
            "¿Mi familia está bien?",
            "¿Qué tengo acordado?",
            "¿Qué me falta en el kit?",
            "¿Quién está cerca?",
            "Necesito 2 cargas para el teléfono en \(model.profile.homeArea.isEmpty ? "Chapinero" : model.profile.homeArea)"
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
                        Label("Falta \(draft.missingFields.map(\.displayName).joined(separator: " y ")).", systemImage: "questionmark.bubble")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(draft.notices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Revisar y publicar") { composing = draft }
                        .buttonStyle(.borderedProminent)
                }
                if let engine = turn.engine {
                    Text(engine.displayName)
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
        HStack(spacing: 10) {
            TextField("Escríbele a Faro", text: $message, axis: .vertical)
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
        .padding()
        .background(.bar)
    }

    private func send(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isThinking else { return }
        message = ""
        turns.append(Turn(fromUser: true, text: cleaned))
        isThinking = true

        Task {
            defer { isThinking = false }
            if Self.looksLikeRequest(cleaned) {
                let result = await PersonalAgentInterpreter.interpret(cleaned, emergencyNumber: model.profile.country.emergencyNumber)
                var draft = result.draft
                if draft.area.isEmpty { draft.area = model.profile.homeArea }
                turns.append(Turn(fromUser: false, text: draft.summary + " Revísalo antes de publicarlo.", draft: draft, engine: result.engine))
            } else {
                let (answer, engine) = await AgentBrain.answer(cleaned, snapshot: model.snapshot)
                turns.append(Turn(fromUser: false, text: answer, engine: engine))
            }
        }
    }

    /// Needs and offers become drafts; everything else is a question for the agent.
    static func looksLikeRequest(_ text: String) -> Bool {
        let lower = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        guard !lower.contains("?") else { return false }
        let verbs = ["necesito", "necesitamos", "busco", "me falta", "ofrezco", "puedo ofrecer", "puedo ayudar", "tengo", "comparto"]
        return verbs.contains(where: lower.contains) && OfflineAgent.interpret(text).resource != nil
    }
}

extension AgentDraft: Identifiable {
    public var id: String { originalText + kind.rawValue }
}
