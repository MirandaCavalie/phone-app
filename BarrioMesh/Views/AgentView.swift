import SwiftUI

struct AgentView: View {
    @EnvironmentObject private var model: AppModel

    @State private var message = ""
    @State private var draft: AgentDraft?
    @State private var engine: AgentEngine?
    @State private var isThinking = false
    @State private var showingComposer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    composerCard

                    if let draft {
                        interpretationCard(draft)
                    }

                    memoryCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mi agente")
            .sheet(isPresented: $showingComposer) {
                if let draft {
                    PostComposerView(kind: draft.kind, initialDraft: draft)
                }
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Un agente que se queda con vos", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.indigo)

            Text("Entiende lo que necesitás o podés ofrecer, recuerda el pedido y busca ayuda en teléfonos cercanos.")

            Label("Se procesa en este iPhone. No necesita internet ni una API.", systemImage: "iphone.and.arrow.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contale la situación")
                .font(.headline)

            TextField(
                "Ejemplo: Necesito 2 botellas de agua en Mission, urgente",
                text: $message,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)

            Button {
                Task { await understandMessage() }
            } label: {
                if isThinking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Entender sin internet", systemImage: "brain.head.profile")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    example("Necesito 2 botellas de agua en Mission, urgente")
                    example("Tengo un power bank para ofrecer en SOMA")
                    example("Necesito traducción en Chinatown")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func interpretationCard(_ draft: AgentDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Esto entendí", systemImage: "quote.bubble.fill")
                    .font(.headline)
                Spacer()
                if let engine {
                    Text(engine.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
            }

            Text(draft.summary)

            if !draft.missingFields.isEmpty {
                Label(
                    "Falta completar \(draft.missingFields.map(\.displayName).joined(separator: " y ")).",
                    systemImage: "questionmark.bubble"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            }

            ForEach(draft.notices, id: \.self) { notice in
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                showingComposer = true
            } label: {
                Label("Revisar antes de publicar", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("El agente nunca publica, confirma ni comparte datos sin tu aprobación.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Memoria local", systemImage: "internaldrive.fill")
                .font(.headline)
            Text("\(model.activePosts.count) publicaciones conocidas · \(model.matchSummaries.count) coincidencias")
                .foregroundStyle(.secondary)

            if !model.matchSummaries.isEmpty {
                Label("Encontré ayuda posible. Revisala en Matches.", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func example(_ text: String) -> some View {
        Button(text) {
            message = text
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }

    @MainActor
    private func understandMessage() async {
        isThinking = true
        defer { isThinking = false }
        let result = await PersonalAgentInterpreter.interpret(message)
        draft = result.draft
        engine = result.engine
    }
}
