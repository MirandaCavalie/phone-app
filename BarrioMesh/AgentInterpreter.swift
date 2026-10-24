import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AgentEngine: Sendable {
    case appleIntelligence
    case localRules

    var displayName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence local"
        case .localRules: "Intérprete local"
        }
    }
}

struct PersonalAgentResult: Sendable {
    let draft: AgentDraft
    let engine: AgentEngine
}

enum PersonalAgentInterpreter {
    static func interpret(_ text: String) async -> PersonalAgentResult {
        let fallback = OfflineAgent.interpret(text)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let draft = try await interpretWithAppleIntelligence(text, fallback: fallback)
                return PersonalAgentResult(draft: draft, engine: .appleIntelligence)
            } catch {
                // Model availability can change at runtime. The deterministic parser
                // keeps the emergency flow usable without a network or model download.
            }
        }
        #endif

        return PersonalAgentResult(draft: fallback, engine: .localRules)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A structured need or offer for a neighborhood mutual-aid network")
private struct FoundationAgentDraft {
    @Guide(description: "Whether the person needs help or is offering help", .anyOf(["need", "offer"]))
    var kind: String

    @Guide(description: "The resource category", .anyOf(["water", "power", "transport", "translation", "medicine", "firstAid"]))
    var resource: String

    @Guide(description: "Requested or offered quantity", .range(1...99))
    var quantity: Int

    @Guide(description: "Urgency level", .anyOf(["normal", "important", "urgent"]))
    var urgency: String

    @Guide(description: "Approximate neighborhood only. Return an empty string if none is provided or if it looks like an exact address.")
    var area: String
}

@available(iOS 26.0, *)
private extension PersonalAgentInterpreter {
    static func interpretWithAppleIntelligence(
        _ text: String,
        fallback: AgentDraft
    ) async throws -> AgentDraft {
        let model = SystemLanguageModel(useCase: .contentTagging)
        let session = LanguageModelSession(
            model: model,
            instructions: """
            Extract a structured mutual-aid request from Spanish or English text.
            Never give medical advice, diagnose, or invent missing information.
            Use only an approximate neighborhood; never preserve a street address.
            """
        )
        let response = try await session.respond(
            to: text,
            generating: FoundationAgentDraft.self
        )
        let extracted = response.content
        let resource = ResourceKind(rawValue: extracted.resource) ?? fallback.resource
        let area = OfflineAgent.sanitizeAreaCandidate(extracted.area)

        return AgentDraft(
            kind: PostKind(rawValue: extracted.kind) ?? fallback.kind,
            resource: resource,
            quantity: extracted.quantity,
            unit: resource?.defaultUnit ?? fallback.unit,
            urgency: urgency(from: extracted.urgency) ?? fallback.urgency,
            area: area.isEmpty ? fallback.area : area,
            originalText: text,
            notices: fallback.notices
        )
    }

    static func urgency(from value: String) -> Urgency? {
        switch value {
        case "urgent": .urgent
        case "important": .important
        case "normal": .normal
        default: nil
        }
    }
}
#endif
