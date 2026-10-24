import Foundation

/// Turns a calm, conversational description of a household into an agent profile.
/// Deterministic and offline; the app layers Apple's on-device model on top when available.
public enum ProfileInterpreter {
    public struct Result: Equatable, Sendable {
        public var profile: AgentProfile
        /// Plain-language list of what the agent learned, shown back for review.
        public var learned: [String]
    }

    public static func interpret(_ text: String, into base: AgentProfile = AgentProfile()) -> Result {
        var profile = base
        var learned: [String] = []
        let normalized = OfflineAgent.normalize(text)

        let area = OfflineAgent.extractSafeArea(from: text)
        if !area.isEmpty, profile.homeArea.isEmpty {
            profile.homeArea = area
            learned.append(t("Vives cerca de \(area).", "You live near \(area)."))
        }

        for clause in clauses(in: text) {
            let lower = OfflineAgent.normalize(clause)

            for relation in relations where lower.contains(relation.term) {
                guard !profile.household.contains(where: { OfflineAgent.normalize($0.relation) == OfflineAgent.normalize(relation.label) }) else { continue }
                let depends = dependentResources(in: lower)
                profile.household.append(HouseholdMember(name: relation.label.capitalized, relation: relation.label, dependsOn: depends))
                let names = depends.map(\.displayName).joined(separator: t(" y ", " and ")).lowercased()
                learned.append(depends.isEmpty
                    ? t("Vives con tu \(relation.label).", "You live with your \(relation.label).")
                    : t("Vives con tu \(relation.label), que depende de \(names).", "You live with your \(relation.label), who relies on \(names)."))
            }

            if containsAny(lower, ["tengo", "tenemos", "dispongo", "guardo", "contamos con", "i have", "we have", "i own", "we keep"]), !containsAny(lower, ["no tenemos", "no tengo", "do not have", "dont have"]) {
                if let resource = OfflineAgent.detectResource(in: lower), !isDependentClause(lower) {
                    let quantity = resource == .transport ? 3 : OfflineAgent.detectQuantity(in: lower)
                    upsertSupply(resource, quantity: quantity, in: &profile)
                    learned.append(t("Tienes \(resource.amount(quantity)).", "You have \(resource.amount(quantity))."))
                }
            }

            if containsAny(lower, ["necesito", "necesitamos", "nos falta", "me falta", "no tengo", "no tenemos", "we need", "i need", "do not have", "dont have", "running out"]),
               let resource = OfflineAgent.detectResource(in: lower),
               !profile.standingNeeds.contains(where: { $0.resource == resource }) {
                profile.standingNeeds.append(StandingNeed(
                    resource: resource,
                    quantity: OfflineAgent.detectQuantity(in: lower),
                    urgency: OfflineAgent.detectUrgency(in: lower) == .normal ? .important : OfflineAgent.detectUrgency(in: lower),
                    reason: clause.trimmingCharacters(in: .whitespaces)
                ))
                learned.append(t("En una emergencia, vas a necesitar \(resource.displayName.lowercased()).", "In an emergency you will need \(resource.displayName.lowercased())."))
            }
        }

        if containsAny(normalized, ["soy enfermer", "soy medic", "soy paramedic", "primeros auxilios", "soy bombero", "soy rescatista", "i am a nurse", "i am a doctor", "paramedic", "first aid", "firefighter", "emt"]) {
            upsertSupply(.firstAid, quantity: 1, in: &profile)
            learned.append(t("Sabes dar primeros auxilios.", "You can give first aid."))
        }
        if containsAny(normalized, ["hablo ingles", "hablo portugues", "hablo frances", "soy traductor", "soy interprete", "bilingue", "i speak spanish", "i speak", "bilingual", "translator", "interpreter"]) {
            upsertSupply(.translation, quantity: 1, in: &profile)
            learned.append(t("Puedes ayudar a traducir.", "You can help translate."))
        }

        return Result(profile: profile, learned: learned)
    }

    private struct Relation {
        let term: String
        let label: String
    }

    private static let relations: [Relation] = [
        Relation(term: "mama", label: "mamá"), Relation(term: "madre", label: "mamá"),
        Relation(term: "papa ", label: "papá"), Relation(term: "padre", label: "papá"),
        Relation(term: "abuela", label: "abuela"), Relation(term: "abuelo", label: "abuelo"),
        Relation(term: "hija", label: "hija"), Relation(term: "hijo", label: "hijo"),
        Relation(term: "bebe", label: "bebé"), Relation(term: "esposa", label: "esposa"),
        Relation(term: "esposo", label: "esposo"), Relation(term: "pareja", label: "pareja"),
        Relation(term: "hermana", label: "hermana"), Relation(term: "hermano", label: "hermano"),
        Relation(term: "my mom", label: "mom"), Relation(term: "my mother", label: "mom"),
        Relation(term: "my dad", label: "dad"), Relation(term: "my father", label: "dad"),
        Relation(term: "grandma", label: "grandma"), Relation(term: "grandmother", label: "grandma"),
        Relation(term: "grandpa", label: "grandpa"), Relation(term: "grandfather", label: "grandpa"),
        Relation(term: "daughter", label: "daughter"), Relation(term: "my son", label: "son"),
        Relation(term: "baby", label: "baby"), Relation(term: "my wife", label: "wife"),
        Relation(term: "husband", label: "husband"), Relation(term: "partner", label: "partner"),
        Relation(term: "sister", label: "sister"), Relation(term: "brother", label: "brother")
    ]

    private static func dependentResources(in clause: String) -> [ResourceKind] {
        var result: [ResourceKind] = []
        if containsAny(clause, ["insulina", "medicamento", "medicina", "pastilla", "tratamiento", "remedio", "insulin", "medication", "medicine", "pills", "treatment"]) { result.append(.medicine) }
        if containsAny(clause, ["oxigeno", "concentrador", "maquina", "silla electrica", "nebulizador", "oxygen", "cpap", "wheelchair", "nebulizer", "dialysis"]) { result.append(.power) }
        return result
    }

    private static func isDependentClause(_ clause: String) -> Bool {
        relations.contains(where: { clause.contains($0.term) }) && !dependentResources(in: clause).isEmpty
    }

    private static func upsertSupply(_ resource: ResourceKind, quantity: Int, in profile: inout AgentProfile) {
        // Keep half of consumables for the household; skills and seats can be shared in full.
        let reserve = [.water, .power, .medicine].contains(resource) ? quantity / 2 : 0
        if let index = profile.supplies.firstIndex(where: { $0.resource == resource }) {
            profile.supplies[index].quantity = max(profile.supplies[index].quantity, quantity)
            profile.supplies[index].reserve = max(profile.supplies[index].reserve, reserve)
        } else {
            profile.supplies.append(Supply(resource: resource, quantity: quantity, reserve: reserve))
        }
    }

    private static func clauses(in text: String) -> [String] {
        text
            .replacingOccurrences(of: " y ", with: ",")
            .replacingOccurrences(of: " pero ", with: ",")
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " but ", with: ",")
            .split(whereSeparator: { ",.;\n".contains($0) })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }
}
