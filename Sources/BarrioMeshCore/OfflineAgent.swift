import Foundation

public enum AgentMissingField: String, Equatable, Sendable {
    case resource
    case area

    public var displayName: String {
        switch self {
        case .resource: t("el tipo de ayuda", "the kind of help")
        case .area: t("una zona aproximada", "an approximate area")
        }
    }
}

public struct AgentDraft: Equatable, Sendable {
    public var kind: PostKind
    public var resource: ResourceKind?
    public var quantity: Int
    public var unit: String
    public var urgency: Urgency
    public var area: String
    public var note: String
    public var originalText: String
    public var notices: [String]

    public init(
        kind: PostKind,
        resource: ResourceKind?,
        quantity: Int,
        unit: String,
        urgency: Urgency,
        area: String,
        note: String = "",
        originalText: String,
        notices: [String] = []
    ) {
        self.kind = kind
        self.resource = resource
        self.quantity = max(1, min(quantity, 99))
        self.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urgency = urgency
        self.area = area.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalText = originalText
        self.notices = notices
    }

    public var missingFields: [AgentMissingField] {
        var fields: [AgentMissingField] = []
        if resource == nil { fields.append(.resource) }
        if area.isEmpty { fields.append(.area) }
        return fields
    }

    public var isReady: Bool { missingFields.isEmpty }

    public var summary: String {
        let what = resource?.amount(quantity) ?? t("un recurso por elegir", "a resource to choose")
        let location = area.isEmpty ? t("una zona por completar", "an area to fill in") : area
        return kind == .need
            ? t("Necesitas \(what) en \(location) (\(urgency.displayName.lowercased())).", "You need \(what) in \(location) (\(urgency.displayName.lowercased())).")
            : t("Puedes ofrecer \(what) en \(location).", "You can offer \(what) in \(location).")
    }
}

public enum OfflineAgent {
    public static func interpret(_ text: String, emergencyNumber: String = "911") -> AgentDraft {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(cleaned)
        let kind = detectKind(in: normalized)
        let resource = detectResource(in: normalized)
        let quantity = detectQuantity(in: normalized)
        let urgency = detectUrgency(in: normalized)
        let area = extractSafeArea(from: cleaned)
        let unit = resource?.defaultUnit ?? "unidad"

        var notices: [String] = []
        if containsPossibleExactAddress(normalized) {
            notices.append(t("No guardé la dirección exacta. Escribe solo una zona.", "I did not keep the exact address. Use an approximate area."))
        }
        if containsMedicalEmergency(normalized) {
            notices.append(t("Puede ser una emergencia médica: llama al \(emergencyNumber).", "This may be a medical emergency: call \(emergencyNumber)."))
        }

        return AgentDraft(
            kind: kind,
            resource: resource,
            quantity: quantity,
            unit: unit,
            urgency: urgency,
            area: area,
            originalText: cleaned,
            notices: notices
        )
    }

    public static func extractSafeArea(from text: String) -> String {
        let normalized = normalize(text)
        guard !containsPossibleExactAddress(normalized) else { return "" }

        for area in knownAreas where normalized.contains(normalize(area)) {
            return area
        }

        let pattern = #"(?i)(?:\ben\b|\bzona\b|\bpor\b|\bcerca\s+de\b|\barea\b|\bárea\b|\bin\b|\bnear\b)\s+([^,.!?]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return ""
        }

        let stopWords: Set<String> = [
            "urgente", "importante", "hoy", "ahora", "ya", "porque", "para", "pero", "y", "urgent", "today", "now", "please", "and", "but"
        ]
        let words = text[range]
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        let areaWords = words.prefix(while: { !stopWords.contains(normalize($0)) })
        return sanitizeAreaCandidate(areaWords.joined(separator: " "))
    }

    public static func sanitizeAreaCandidate(_ candidate: String) -> String {
        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !containsPossibleExactAddress(normalize(cleaned)) else { return "" }
        return cleaned.split(whereSeparator: { $0.isWhitespace }).prefix(4).joined(separator: " ")
    }

    private static func detectKind(in text: String) -> PostKind {
        let offerTerms = [
            "puedo ayudar", "puedo ofrecer", "ofrezco", "tengo disponible", "tengo ", "dispongo",
            "comparto", "i can help", "i can offer", "i have", "we have", "available"
        ]
        let needTerms = [
            "necesito", "necesitamos", "busco", "hace falta", "me falta", "need", "looking for", "no tenemos", "we do not have"
        ]

        let offerIndex = firstIndex(ofAny: offerTerms, in: text)
        let needIndex = firstIndex(ofAny: needTerms, in: text)

        switch (offerIndex, needIndex) {
        case let (offer?, need?):
            return offer < need ? PostKind.offer : PostKind.need
        case (.some, .none):
            return .offer
        default:
            return .need
        }
    }

    static func detectResource(in text: String) -> ResourceKind? {
        let terms: [(ResourceKind, [String])] = [
            (.water, ["agua", "botella", "water", "bottle"]),
            (.power, ["bateria", "cargador", "cargar", "carga", "energia", "electricidad", "power bank", "charger", "battery"]),
            (.transport, ["transporte", "auto", "carro", "vehiculo", "asiento", "llevar", "ride", "transport", "car"]),
            (.translation, ["traduccion", "traducir", "interprete", "translation", "translator"]),
            (.medicine, ["medicamento", "medicina", "remedio", "receta", "insulina", "pastilla", "medicine", "medication"]),
            (.firstAid, ["primeros auxilios", "botiquin", "venda", "curacion", "first aid", "bandage"])
        ]

        return terms
            .compactMap { resource, keywords in
                firstIndex(ofAny: keywords, in: text).map { (resource, $0) }
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    static func detectQuantity(in text: String) -> Int {
        if let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])(\d{1,2})(?![\p{L}\p{N}])"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let value = Int(text[range]) {
            return max(1, min(value, 99))
        }

        let wordValues = [
            "una": 1, "uno": 1, "un": 1, "one": 1,
            "dos": 2, "two": 2, "tres": 3, "three": 3,
            "cuatro": 4, "four": 4, "cinco": 5, "five": 5
        ]
        for word in text.split(whereSeparator: { !$0.isLetter }) {
            if let value = wordValues[String(word)] { return value }
        }
        return 1
    }

    static func detectUrgency(in text: String) -> Urgency {
        if ["urgente", "emergencia", "inmediato", "ahora", "urgent", "emergency"].contains(where: text.contains) {
            return .urgent
        }
        if ["importante", "pronto", "hoy", "important", "soon", "today"].contains(where: text.contains) {
            return .important
        }
        return .normal
    }

    private static func containsPossibleExactAddress(_ text: String) -> Bool {
        let hasNumber = text.range(of: #"\d"#, options: .regularExpression) != nil
        let addressTerms = ["calle", "avenida", "av.", "street", "st.", "road", "rd.", "numero", "#"]
        return hasNumber && addressTerms.contains(where: text.contains)
    }

    private static func containsMedicalEmergency(_ text: String) -> Bool {
        [
            "no respira", "inconsciente", "dolor de pecho", "hemorragia", "sobredosis",
            "derrame cerebral", "cannot breathe", "unconscious", "chest pain", "overdose"
        ].contains(where: text.contains)
    }

    private static func firstIndex(ofAny terms: [String], in text: String) -> String.Index? {
        terms.compactMap { text.range(of: $0)?.lowerBound }.min()
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
    }

    static let knownAreas = [
        // Colombia
        "Chapinero", "Usaquén", "Suba", "Kennedy", "Bosa", "Teusaquillo", "La Candelaria",
        "El Poblado", "Laureles", "Belén", "Envigado", "Granada", "San Antonio",
        // Venezuela
        "Chacao", "Altamira", "Petare", "Catia", "El Hatillo", "Los Palos Grandes",
        // México, Chile, Perú, Ecuador
        "Roma Norte", "Condesa", "Coyoacán", "Iztapalapa", "Providencia", "Ñuñoa", "Miraflores",
        "Barranco", "La Mariscal",
        // San Francisco
        "Mission", "SOMA", "Tenderloin", "Chinatown", "Sunset", "Richmond", "Castro",
        "Marina", "Bernal Heights", "Excelsior", "Bayview", "Potrero Hill", "Noe Valley", "Downtown"
    ]
}
