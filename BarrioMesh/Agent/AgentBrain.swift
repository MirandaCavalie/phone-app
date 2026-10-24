import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A read-only picture of what the agent knows, handed to the language model's tools.
struct AgentSnapshot: Sendable {
    let profile: AgentProfile
    let policy: AgentPolicy
    let memory: AgentMemory
    let state: MeshState
    let selfID: String
    let connectedPeers: Int
    let hasInternet: Bool

    var familyLines: [String] {
        state.latestCheckIns(circleCode: profile.familyCircleCode)
            .filter { $0.authorID != selfID }
            .map { "\($0.authorName): \($0.status.displayName.lowercased()) · \($0.area) · \(Self.time($0.createdAt))" }
    }

    var agreementLines: [String] {
        state.proposals.compactMap { proposal in
            guard let terms = state.negotiation(for: proposal.id).agreedTerms,
                  let need = state.posts.first(where: { $0.id == proposal.needID }),
                  let offer = state.posts.first(where: { $0.id == proposal.offerID }),
                  need.authorID == selfID || offer.authorID == selfID else { return nil }
            let other = need.authorID == selfID ? offer.authorName : need.authorName
            let done = proposal.completions.contains(selfID) ? t(" (entregado)", " (delivered)") : ""
            return "\(need.resource.amount(terms.quantity)) · \(other) · \(terms.meetingPoint) · \(Self.time(terms.meetAt))\(done)"
        }
    }

    var neighborhoodLines: [String] {
        state.posts.filter { $0.isActive() && $0.authorID != selfID }.map {
            "\($0.authorName) \($0.kind == .need ? t("necesita", "needs") : t("ofrece", "offers")) \($0.resource.amount($0.quantity)) · \($0.area)"
        }
    }

    var profileLines: [String] {
        var lines = ["Name: \(profile.name)", "Area: \(profile.homeArea)", "Country: \(profile.country.displayName), emergency number \(profile.country.emergencyNumber)"]
        lines += profile.household.map { "Lives with: \($0.name) (\($0.relation))" + ($0.dependsOn.isEmpty ? "" : ", relies on \($0.dependsOn.map(\.rawValue).joined(separator: ", "))") }
        lines += profile.supplies.map { "Has \($0.quantity) \($0.resource.rawValue), reserve \($0.reserve)" }
        lines += profile.preparedness.gaps.map { "Gap: \($0)" }
        return lines
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

enum AgentBrain {
    // MARK: Onboarding

    static func learnProfile(from text: String, base: AgentProfile) async -> (ProfileInterpreter.Result, AgentEngine) {
        let fallback = ProfileInterpreter.interpret(text, into: base)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let result = try? await learnWithModel(text, base: base, fallback: fallback) {
                return (result, .appleIntelligence)
            }
        }
        #endif
        return (fallback, .localRules)
    }

    // MARK: Questions

    static func answer(_ question: String, snapshot: AgentSnapshot) async -> (String, AgentEngine) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let answer = try? await answerWithModel(question, snapshot: snapshot) {
                return (answer, .appleIntelligence)
            }
        }
        #endif
        return (localAnswer(question, snapshot: snapshot), .localRules)
    }

    static func localAnswer(_ question: String, snapshot: AgentSnapshot) -> String {
        let q = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))

        if ["familia", "mama", "papa", "hijo", "hija", "abuel", "estan bien", "esta bien", "family", "mom", "dad", "son", "daughter", "grand", "okay", " ok"].contains(where: q.contains) {
            let lines = snapshot.familyLines
            if snapshot.profile.familyCircleID == nil {
                return t("Aún no tienes código de familia. Créalo en Familia y compártelo.", "You don't have a family code yet. Create it in Family and share it.")
            }
            return lines.isEmpty
                ? t("Aún no llega ningún aviso de tu familia. Sigo escuchando.", "No word from your family yet. I'm still listening.")
                : t("Lo último de tu familia:\n• ", "Latest from your family:\n• ") + lines.joined(separator: "\n• ")
        }

        if ["preparad", "kit", "falta", "listo", "mochila", "prepared", "ready", "missing"].contains(where: q.contains) {
            let report = snapshot.profile.preparedness
            return report.gaps.isEmpty
                ? t("Tu hogar está listo (\(report.score)/100).", "Your household is ready (\(report.score)/100).")
                : t("Preparación \(report.score)/100. Falta:\n• ", "Preparedness \(report.score)/100. Missing:\n• ") + report.gaps.joined(separator: "\n• ")
        }

        if ["vecin", "cerca", "quien", "alguien", "ofrece", "necesita", "neighbor", "nearby", "who", "anyone"].contains(where: q.contains) {
            let lines = snapshot.neighborhoodLines
            return lines.isEmpty
                ? t("Aún no veo vecinos. \(snapshot.connectedPeers) teléfonos conectados.", "No neighbors yet. \(snapshot.connectedPeers) phones connected.")
                : t("Cerca de ti:\n• ", "Near you:\n• ") + lines.prefix(6).joined(separator: "\n• ")
        }

        var parts: [String] = []
        parts.append(snapshot.memory.emergencyActive
            ? t("Modo emergencia: trabajo sin internet con \(snapshot.connectedPeers) teléfonos cercanos.", "Emergency mode: working offline with \(snapshot.connectedPeers) nearby phones.")
            : t("Todo tranquilo. Si pasa algo, me activo solo.", "All calm. If something happens, I'll step in."))
        if !snapshot.agreementLines.isEmpty {
            parts.append(t("Acuerdos: ", "Deals: ") + snapshot.agreementLines.joined(separator: "; ") + ".")
        }
        if !snapshot.memory.pending.isEmpty {
            parts.append(t("Tengo \(snapshot.memory.pending.count) pregunta(s) para ti.", "I have \(snapshot.memory.pending.count) question(s) for you."))
        }
        if let latest = snapshot.familyLines.first {
            parts.append(t("Último aviso familiar: \(latest).", "Latest family update: \(latest)."))
        }
        return parts.joined(separator: " ")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A household described by the user for an emergency-preparedness agent")
private struct ModelProfile {
    @Guide(description: "Approximate neighborhood only. Empty string if none or if it looks like an exact address.")
    var area: String

    @Guide(description: "People who live with the user")
    var household: [ModelMember]

    @Guide(description: "Supplies or skills the user has")
    var supplies: [ModelResource]

    @Guide(description: "Things the household lacks and would need in an emergency")
    var needs: [ModelResource]
}

@available(iOS 26.0, *)
@Generable
private struct ModelMember {
    @Guide(description: "Relation to the user in the user's language, e.g. mamá, hijo, mom, son")
    var relation: String

    @Guide(description: "Resources this person depends on. Only the values medicine or power.")
    var dependsOn: [String]
}

@available(iOS 26.0, *)
@Generable
private struct ModelResource {
    @Guide(description: "Resource category", .anyOf(["water", "power", "transport", "translation", "medicine", "firstAid"]))
    var resource: String

    @Guide(description: "Quantity, 1 if unknown", .range(1...99))
    var quantity: Int
}

@available(iOS 26.0, *)
private extension AgentBrain {
    static func learnWithModel(_ text: String, base: AgentProfile, fallback: ProfileInterpreter.Result) async throws -> ProfileInterpreter.Result {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: """
            Extract a household emergency profile from Spanish or English text.
            Only include facts the user stated. Never invent people or supplies.
            Never keep street addresses; only approximate neighborhoods.
            """
        )
        let extracted = try await session.respond(to: text, generating: ModelProfile.self).content

        var profile = base
        var learned: [String] = []
        let area = OfflineAgent.sanitizeAreaCandidate(extracted.area)
        if profile.homeArea.isEmpty {
            profile.homeArea = area.isEmpty ? fallback.profile.homeArea : area
            if !profile.homeArea.isEmpty { learned.append(t("Vives cerca de \(profile.homeArea).", "You live near \(profile.homeArea).")) }
        }
        for member in extracted.household where !member.relation.isEmpty {
            let depends = member.dependsOn.compactMap(ResourceKind.init(rawValue:))
            profile.household.append(HouseholdMember(name: member.relation.capitalized, relation: member.relation, dependsOn: depends))
            let needs = depends.map(\.displayName).joined(separator: t(" y ", " and ")).lowercased()
            learned.append(depends.isEmpty
                ? t("Vives con tu \(member.relation).", "You live with your \(member.relation).")
                : t("Vives con tu \(member.relation), que depende de \(needs).", "You live with your \(member.relation), who relies on \(needs)."))
        }
        for item in extracted.supplies {
            guard let resource = ResourceKind(rawValue: item.resource) else { continue }
            let reserve = [.water, .power, .medicine].contains(resource) ? item.quantity / 2 : 0
            profile.supplies.append(Supply(resource: resource, quantity: item.quantity, reserve: reserve))
            learned.append(t("Tienes \(resource.amount(item.quantity)).", "You have \(resource.amount(item.quantity))."))
        }
        for item in extracted.needs {
            guard let resource = ResourceKind(rawValue: item.resource) else { continue }
            profile.standingNeeds.append(StandingNeed(resource: resource, quantity: item.quantity))
            learned.append(t("En una emergencia, vas a necesitar \(resource.displayName.lowercased()).", "In an emergency you will need \(resource.displayName.lowercased())."))
        }

        // If the model found nothing, the deterministic reading is more useful than an empty one.
        return learned.isEmpty ? fallback : ProfileInterpreter.Result(profile: profile, learned: learned)
    }

    static func answerWithModel(_ question: String, snapshot: AgentSnapshot) async throws -> String {
        let session = LanguageModelSession(
            tools: [
                SnapshotTool(name: "familyStatus", description: "Latest safety check-ins received from the user's family circle", lines: snapshot.familyLines),
                SnapshotTool(name: "agreements", description: "Handoffs the agent agreed with neighbors: what, who, where and when", lines: snapshot.agreementLines),
                SnapshotTool(name: "neighborhood", description: "What nearby neighbors currently need or offer", lines: snapshot.neighborhoodLines),
                SnapshotTool(name: "profile", description: "The user's household, supplies and preparedness gaps", lines: snapshot.profileLines),
                SnapshotTool(name: "recentActivity", description: "The last actions the agent took on the user's behalf", lines: snapshot.memory.log.prefix(10).map { "\(AgentSnapshot.time($0.date)) \($0.title). \($0.detail)" })
            ],
            instructions: """
            You are Faro, the user's personal emergency agent. It runs fully on this phone, without internet.
            Answer in short, warm \(Lang.isSpanish ? "Spanish (tú)" : "English"). Use the tools to look up facts; never invent them.
            Mode: \(snapshot.memory.emergencyActive ? "emergency" : "normal"). Nearby phones connected: \(snapshot.connectedPeers).
            Never give medical diagnoses or dosages. For life-threatening situations tell them to call \(snapshot.profile.country.emergencyNumber).
            """
        )
        return try await session.respond(to: question).content
    }
}

@available(iOS 26.0, *)
private struct SnapshotTool: Tool {
    let name: String
    let description: String
    let lines: [String]

    @Generable
    struct Arguments {
        @Guide(description: "Optional keyword to filter results; empty for everything")
        var filter: String
    }

    func call(arguments: Arguments) async throws -> String {
        let keyword = arguments.filter.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = keyword.isEmpty ? lines : lines.filter { $0.lowercased().contains(keyword) }
        let result = matching.isEmpty ? lines : matching
        return result.isEmpty ? "No data." : result.joined(separator: "\n")
    }
}
#endif
