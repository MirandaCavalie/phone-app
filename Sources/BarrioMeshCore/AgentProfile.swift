import CryptoKit
import Foundation

/// What the personal agent knows about its person. It lives only on this phone:
/// the agent derives small, shareable posts from it, but never broadcasts the profile itself.
public struct AgentProfile: Codable, Equatable, Sendable {
    public var name: String
    public var country: Country
    public var homeArea: String
    /// A public, easy-to-find place the agent suggests for handoffs (never the home address).
    public var meetingPoint: String
    public var household: [HouseholdMember]
    public var supplies: [Supply]
    public var standingNeeds: [StandingNeed]
    public var familyContacts: [FamilyContact]
    /// Shared secret typed on every phone of the same family. Check-ins are tagged
    /// with a hash of it, so only the family recognizes each other's status.
    public var familyCircleCode: String

    public init(
        name: String = "",
        country: Country = .colombia,
        homeArea: String = "",
        meetingPoint: String = "",
        household: [HouseholdMember] = [],
        supplies: [Supply] = [],
        standingNeeds: [StandingNeed] = [],
        familyContacts: [FamilyContact] = [],
        familyCircleCode: String = ""
    ) {
        self.name = name
        self.country = country
        self.homeArea = homeArea
        self.meetingPoint = meetingPoint
        self.household = household
        self.supplies = supplies
        self.standingNeeds = standingNeeds
        self.familyContacts = familyContacts
        self.familyCircleCode = familyCircleCode
    }

    public var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !homeArea.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var familyCircleID: String? {
        FamilyCircle.identifier(for: familyCircleCode)
    }

    /// How ready the household is for an outage, from 0 to 100.
    /// Approximate location used only to measure distance to official alerts. Never shared.
    public var approximateLocation: (point: GeoPoint, label: String) {
        Places.locate(area: homeArea, country: country)
    }

    public var preparedness: PreparednessReport {
        Preparedness.evaluate(self)
    }
}

public enum Country: String, Codable, CaseIterable, Identifiable, Sendable {
    case colombia
    case venezuela
    case mexico
    case chile
    case peru
    case ecuador
    case argentina
    case unitedStates

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .colombia: "Colombia"
        case .venezuela: "Venezuela"
        case .mexico: "México"
        case .chile: "Chile"
        case .peru: "Perú"
        case .ecuador: "Ecuador"
        case .argentina: "Argentina"
        case .unitedStates: "Estados Unidos"
        }
    }

    public var emergencyNumber: String {
        switch self {
        case .colombia: "123"
        case .venezuela, .mexico, .ecuador, .argentina, .unitedStates: "911"
        case .chile: "131"
        case .peru: "116"
        }
    }

    public var flag: String {
        switch self {
        case .colombia: "🇨🇴"
        case .venezuela: "🇻🇪"
        case .mexico: "🇲🇽"
        case .chile: "🇨🇱"
        case .peru: "🇵🇪"
        case .ecuador: "🇪🇨"
        case .argentina: "🇦🇷"
        case .unitedStates: "🇺🇸"
        }
    }
}

public struct HouseholdMember: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var relation: String
    /// Resources this person depends on (e.g. medicine for insulin, power for oxygen).
    public var dependsOn: [ResourceKind]

    public init(id: UUID = UUID(), name: String, relation: String, dependsOn: [ResourceKind] = []) {
        self.id = id
        self.name = name
        self.relation = relation
        self.dependsOn = dependsOn
    }
}

public struct Supply: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var resource: ResourceKind
    public var quantity: Int
    /// The agent never offers more than `quantity - reserve`, so the household keeps what it needs.
    public var reserve: Int

    public init(id: UUID = UUID(), resource: ResourceKind, quantity: Int, reserve: Int = 0) {
        self.id = id
        self.resource = resource
        self.quantity = max(0, quantity)
        self.reserve = max(0, reserve)
    }

    public var shareable: Int { max(0, quantity - reserve) }
}

public struct StandingNeed: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var resource: ResourceKind
    public var quantity: Int
    public var urgency: Urgency
    public var reason: String

    public init(id: UUID = UUID(), resource: ResourceKind, quantity: Int = 1, urgency: Urgency = .important, reason: String = "") {
        self.id = id
        self.resource = resource
        self.quantity = max(1, quantity)
        self.urgency = urgency
        self.reason = reason
    }
}

public struct FamilyContact: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// International format without symbols, e.g. 573001234567. Used only for SMS/WhatsApp handoffs.
    public var phone: String

    public init(id: UUID = UUID(), name: String, phone: String) {
        self.id = id
        self.name = name
        self.phone = phone.filter(\.isNumber)
    }
}

public enum FamilyCircle {
    /// A short, stable, non-reversible tag for a family code. Not cryptographic security —
    /// it only avoids broadcasting the code itself to every nearby phone.
    /// A stable tag derived from the family code. Phones use it to recognize their circle;
    /// the readable content of a check-in is additionally encrypted (see `SafetyCheckIn.sealed`).
    public static func identifier(for code: String) -> String? {
        let normalized = normalized(code)
        guard normalized.count >= 4 else { return nil }
        let digest = SHA256.hash(data: Data(("faro-circle-id|" + normalized).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

public struct PreparednessReport: Equatable, Sendable {
    public let score: Int
    public let gaps: [String]
}

enum Preparedness {
    static func evaluate(_ profile: AgentProfile) -> PreparednessReport {
        var score = 0
        var gaps: [String] = []
        let people = max(1, profile.household.count + 1)

        let water = profile.supplies.first(where: { $0.resource == .water })?.quantity ?? 0
        // Rough guide: about 4 liters (≈ 6 small bottles) per person per day, for 3 days.
        let waterTarget = people * 6 * 3
        if water >= waterTarget {
            score += 30
        } else {
            score += water * 30 / max(1, waterTarget)
            gaps.append("Agua: tienes \(water) de \(waterTarget) botellas recomendadas para 3 días.")
        }

        if profile.supplies.contains(where: { $0.resource == .power && $0.quantity > 0 }) {
            score += 15
        } else {
            gaps.append("Sin batería externa: el teléfono es tu único canal con la familia.")
        }

        if profile.supplies.contains(where: { $0.resource == .firstAid && $0.quantity > 0 }) {
            score += 15
        } else {
            gaps.append("Falta un botiquín de primeros auxilios.")
        }

        if profile.familyCircleID != nil {
            score += 20
        } else {
            gaps.append("Crea un código de familia para recibir sus “estoy bien” sin internet.")
        }

        if !profile.familyContacts.isEmpty {
            score += 10
        } else {
            gaps.append("Agrega al menos un contacto de familia para avisarle cuando vuelva la señal.")
        }

        let dependents = profile.household.filter { !$0.dependsOn.isEmpty }
        let uncovered = dependents.filter { member in
            member.dependsOn.contains { resource in
                !profile.supplies.contains(where: { $0.resource == resource && $0.quantity > 0 })
            }
        }
        if uncovered.isEmpty {
            score += 10
        } else {
            for member in uncovered {
                let names = member.dependsOn.map(\.displayName).joined(separator: ", ").lowercased()
                gaps.append("\(member.name) depende de \(names): conviene tener reserva.")
            }
        }

        return PreparednessReport(score: min(100, score), gaps: gaps)
    }
}
