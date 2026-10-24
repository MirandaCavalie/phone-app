import Foundation

public enum ResourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case power
    case transport
    case translation
    case medicine
    case firstAid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .water: t("Agua", "Water")
        case .power: t("Energía", "Power")
        case .transport: t("Transporte", "Transport")
        case .translation: t("Traducción", "Translation")
        case .medicine: t("Medicamentos", "Medicine")
        case .firstAid: t("Primeros auxilios", "First aid")
        }
    }

    public var systemImage: String {
        switch self {
        case .water: "drop.fill"
        case .power: "bolt.fill"
        case .transport: "car.fill"
        case .translation: "character.bubble.fill"
        case .medicine: "pills.fill"
        case .firstAid: "cross.case.fill"
        }
    }

    public var defaultUnit: String { unit(plural: true) }

    public func unit(plural: Bool) -> String {
        switch self {
        case .water: plural ? t("botellas", "bottles") : t("botella", "bottle")
        case .power: plural ? t("cargas", "charges") : t("carga", "charge")
        case .transport: plural ? t("lugares", "seats") : t("lugar", "seat")
        case .translation: plural ? t("personas", "people") : t("persona", "person")
        case .medicine: plural ? t("unidades", "units") : t("unidad", "unit")
        case .firstAid: plural ? t("kits", "kits") : "kit"
        }
    }

    /// "4 botellas de agua" / "4 bottles of water".
    public func amount(_ quantity: Int) -> String {
        "\(quantity) \(unit(plural: quantity != 1)) \(t("de", "of")) \(displayName.lowercased())"
    }

    /// "4 botellas" / "4 bottles".
    public func count(_ quantity: Int) -> String {
        "\(quantity) \(unit(plural: quantity != 1))"
    }
}

public enum PostKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case need
    case offer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .need: t("Necesito", "I need")
        case .offer: t("Puedo ofrecer", "I can offer")
        }
    }
}

public enum Urgency: Int, Codable, CaseIterable, Identifiable, Sendable {
    case normal = 1
    case important = 2
    case urgent = 3

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .important: t("Importante", "Important")
        case .urgent: t("Urgente", "Urgent")
        }
    }
}
