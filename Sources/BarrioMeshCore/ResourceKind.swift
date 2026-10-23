import Foundation

public enum ResourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case water
    case power
    case transport
    case translation
    case firstAid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .water: "Agua"
        case .power: "Energía"
        case .transport: "Transporte"
        case .translation: "Traducción"
        case .firstAid: "Primeros auxilios"
        }
    }

    public var systemImage: String {
        switch self {
        case .water: "drop.fill"
        case .power: "bolt.fill"
        case .transport: "car.fill"
        case .translation: "character.bubble.fill"
        case .firstAid: "cross.case.fill"
        }
    }

    public var defaultUnit: String {
        switch self {
        case .water: "botellas"
        case .power: "cargas"
        case .transport: "lugares"
        case .translation: "persona"
        case .firstAid: "kit"
        }
    }
}

public enum PostKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case need
    case offer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .need: "Necesito"
        case .offer: "Puedo ofrecer"
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
        case .important: "Importante"
        case .urgent: "Urgente"
        }
    }
}
