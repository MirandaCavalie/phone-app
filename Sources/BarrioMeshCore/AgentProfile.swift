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
    /// The emergency go-bag inventory the agent keeps an eye on.
    public var goBag: [GoBagItem]
    /// A neighborhood store or pharmacy the agent can prepare WhatsApp orders for.
    public var trustedStore: FamilyContact?

    public init(
        name: String = "",
        country: Country = .colombia,
        homeArea: String = "",
        meetingPoint: String = "",
        household: [HouseholdMember] = [],
        supplies: [Supply] = [],
        standingNeeds: [StandingNeed] = [],
        familyContacts: [FamilyContact] = [],
        familyCircleCode: String = "",
        goBag: [GoBagItem] = [],
        trustedStore: FamilyContact? = nil
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
        self.goBag = goBag
        self.trustedStore = trustedStore
    }

    public init(from decoder: Decoder) throws {
        // Profiles saved by older builds keep loading as fields are added.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try c.decodeIfPresent(Country.self, forKey: .country) ?? .colombia
        homeArea = try c.decodeIfPresent(String.self, forKey: .homeArea) ?? ""
        meetingPoint = try c.decodeIfPresent(String.self, forKey: .meetingPoint) ?? ""
        household = try c.decodeIfPresent([HouseholdMember].self, forKey: .household) ?? []
        supplies = try c.decodeIfPresent([Supply].self, forKey: .supplies) ?? []
        standingNeeds = try c.decodeIfPresent([StandingNeed].self, forKey: .standingNeeds) ?? []
        familyContacts = try c.decodeIfPresent([FamilyContact].self, forKey: .familyContacts) ?? []
        familyCircleCode = try c.decodeIfPresent(String.self, forKey: .familyCircleCode) ?? ""
        goBag = try c.decodeIfPresent([GoBagItem].self, forKey: .goBag) ?? []
        trustedStore = try c.decodeIfPresent(FamilyContact.self, forKey: .trustedStore)
    }

    public var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !homeArea.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// People who live in the same home as the user (relatives elsewhere are in `household` too).
    public var housemates: [HouseholdMember] { household.filter(\.livesWithUser) }

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
        case .mexico: t("México", "Mexico")
        case .chile: "Chile"
        case .peru: t("Perú", "Peru")
        case .ecuador: "Ecuador"
        case .argentina: "Argentina"
        case .unitedStates: t("Estados Unidos", "United States")
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

    public var iso3: String {
        switch self {
        case .colombia: "COL"
        case .venezuela: "VEN"
        case .mexico: "MEX"
        case .chile: "CHL"
        case .peru: "PER"
        case .ecuador: "ECU"
        case .argentina: "ARG"
        case .unitedStates: "USA"
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
    /// False for relatives in the family circle who live elsewhere (a son at university).
    public var livesWithUser: Bool
    public var phone: String
    public var medical: MedicalCard
    public var routine: [RoutineBlock]

    public init(
        id: UUID = UUID(),
        name: String,
        relation: String,
        dependsOn: [ResourceKind] = [],
        livesWithUser: Bool = true,
        phone: String = "",
        medical: MedicalCard = MedicalCard(),
        routine: [RoutineBlock] = []
    ) {
        self.id = id
        self.name = name
        self.relation = relation
        self.dependsOn = dependsOn
        self.livesWithUser = livesWithUser
        self.phone = phone.filter(\.isNumber)
        self.medical = medical
        self.routine = routine
    }

    public init(from decoder: Decoder) throws {
        // Profiles saved before medical cards and routines existed keep loading.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        relation = try c.decode(String.self, forKey: .relation)
        dependsOn = try c.decodeIfPresent([ResourceKind].self, forKey: .dependsOn) ?? []
        livesWithUser = try c.decodeIfPresent(Bool.self, forKey: .livesWithUser) ?? true
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        medical = try c.decodeIfPresent(MedicalCard.self, forKey: .medical) ?? MedicalCard()
        routine = try c.decodeIfPresent([RoutineBlock].self, forKey: .routine) ?? []
    }

    /// Resources this person needs, including what their medical card implies
    /// (refrigerated medication needs power during an outage).
    public var effectiveNeeds: [ResourceKind] {
        var needs = dependsOn
        if !medical.medications.isEmpty, !needs.contains(.medicine) { needs.append(.medicine) }
        if medical.medications.contains(where: \.needsRefrigeration) || medical.usesPoweredDevice, !needs.contains(.power) {
            needs.append(.power)
        }
        return needs
    }

    public var isVulnerable: Bool {
        !effectiveNeeds.isEmpty || medical.mobility != .independent || (medical.age.map { $0 >= 70 || $0 <= 5 } ?? false)
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
        let people = max(1, profile.housemates.count + 1)

        let water = profile.supplies.first(where: { $0.resource == .water })?.quantity ?? 0
        // Rough guide: about 4 liters (≈ 6 small bottles) per person per day, for 3 days.
        let waterTarget = people * 6 * 3
        if water >= waterTarget {
            score += 30
        } else {
            score += water * 30 / max(1, waterTarget)
            gaps.append(t("Agua: tienes \(water) de \(waterTarget) botellas para 3 días.", "Water: \(water) of \(waterTarget) bottles for 3 days."))
        }

        if profile.supplies.contains(where: { $0.resource == .power && $0.quantity > 0 }) {
            score += 15
        } else {
            gaps.append(t("Sin batería externa.", "No power bank."))
        }

        if profile.supplies.contains(where: { $0.resource == .firstAid && $0.quantity > 0 }) {
            score += 15
        } else {
            gaps.append(t("Falta un botiquín.", "No first aid kit."))
        }

        if profile.familyCircleID != nil {
            score += 20
        } else {
            gaps.append(t("Sin código de familia.", "No family code yet."))
        }

        if !profile.familyContacts.isEmpty {
            score += 10
        } else {
            gaps.append(t("Sin contacto de familia.", "No family contact."))
        }

        for member in profile.household {
            for medication in member.medical.medications {
                if let days = medication.supplyDays, days <= 3 {
                    gaps.append(t("\(medication.name) de \(member.name): quedan \(days) días.", "\(member.name)'s \(medication.name): \(days) days left."))
                }
            }
        }

        let dependents = profile.housemates.filter { !$0.effectiveNeeds.isEmpty }
        let uncovered = dependents.filter { member in
            member.effectiveNeeds.contains { resource in
                !profile.supplies.contains(where: { $0.resource == resource && $0.quantity > 0 })
            }
        }
        if uncovered.isEmpty {
            score += 10
        } else {
            for member in uncovered {
                let names = member.effectiveNeeds.map(\.displayName).joined(separator: ", ").lowercased()
                gaps.append(t("\(member.name) depende de \(names): ten reserva.", "\(member.name) relies on \(names): keep a reserve."))
            }
        }

        return PreparednessReport(score: min(100, score), gaps: gaps)
    }
}
