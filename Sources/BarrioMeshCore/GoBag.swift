import Foundation

/// The emergency go-bag: what a household should be able to grab in two minutes.
/// Quantities follow common civil-protection guidance (72 hours, per person).
public enum GoBagKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case water, food, flashlight, batteries, powerBank, radio, firstAidKit, whistle
    case masks, blanket, hygiene, documents, cash, medication

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .water: t("Agua (botella 1 L)", "Water (1 L bottle)")
        case .food: t("Comida no perecible (raciones)", "Non-perishable food (rations)")
        case .flashlight: t("Linterna", "Flashlight")
        case .batteries: t("Pilas", "Batteries")
        case .powerBank: t("Batería externa", "Power bank")
        case .radio: t("Radio a pilas", "Battery radio")
        case .firstAidKit: t("Botiquín", "First aid kit")
        case .whistle: t("Silbato", "Whistle")
        case .masks: t("Mascarillas", "Masks")
        case .blanket: t("Manta térmica", "Emergency blanket")
        case .hygiene: t("Kit de higiene", "Hygiene kit")
        case .documents: t("Copias de documentos", "Document copies")
        case .cash: t("Efectivo en billetes pequeños", "Cash in small bills")
        case .medication: t("Medicamentos", "Medication")
        }
    }

    public var systemImage: String {
        switch self {
        case .water: "drop.fill"
        case .food: "takeoutbag.and.cup.and.straw.fill"
        case .flashlight: "flashlight.on.fill"
        case .batteries: "battery.100"
        case .powerBank: "battery.100.bolt"
        case .radio: "radio.fill"
        case .firstAidKit: "cross.case.fill"
        case .whistle: "speaker.wave.3.fill"
        case .masks: "facemask.fill"
        case .blanket: "bed.double.fill"
        case .hygiene: "hands.and.sparkles.fill"
        case .documents: "doc.on.doc.fill"
        case .cash: "banknote.fill"
        case .medication: "pills.fill"
        }
    }

    /// Months an item stays good before the agent asks to replace it, if it expires.
    public var shelfLifeMonths: Int? {
        switch self {
        case .water: 6
        case .food: 12
        case .batteries: 24
        default: nil
        }
    }

    /// What to type in a store search.
    var searchQuery: String {
        switch self {
        case .water: t("agua mineral 1 litro", "bottled water 1 liter")
        case .food: t("comida enlatada atún", "canned food")
        case .flashlight: t("linterna led", "led flashlight")
        case .batteries: t("pilas AA", "AA batteries")
        case .powerBank: t("power bank 10000 mah", "power bank 10000 mah")
        case .radio: t("radio a pilas", "battery radio")
        case .firstAidKit: t("botiquín primeros auxilios", "first aid kit")
        case .whistle: t("silbato emergencia", "emergency whistle")
        case .masks: t("mascarillas kn95", "kn95 masks")
        case .blanket: t("manta térmica emergencia", "emergency thermal blanket")
        case .hygiene: t("kit de higiene personal", "personal hygiene kit")
        case .documents: t("protector documentos impermeable", "waterproof document pouch")
        case .cash: ""
        case .medication: ""
        }
    }
}

public struct GoBagItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: GoBagKind
    /// For `.medication`: the medication name and whose it is.
    public var label: String
    public var quantity: Int
    public var expiresAt: Date?

    public init(id: UUID = UUID(), kind: GoBagKind, label: String = "", quantity: Int, expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.quantity = max(0, quantity)
        self.expiresAt = expiresAt
    }

    public var name: String { label.isEmpty ? kind.displayName : label }
}

public enum GoBag {
    public struct Requirement: Equatable, Sendable {
        public let kind: GoBagKind
        public let label: String
        public let quantity: Int
        public let reason: String
    }

    public struct Gap: Equatable, Identifiable, Sendable {
        public enum Problem: Equatable, Sendable {
            case missing
            case short(have: Int)
            case expiring(on: Date)
            case expired
        }

        public var id: String { "\(requirement.kind.rawValue):\(requirement.label)" }
        public let requirement: Requirement
        public let problem: Problem
        /// Units to buy to close the gap.
        public let toBuy: Int

        /// Just the problem, for a row that already shows the item's name.
        public var status: String {
            switch problem {
            case .missing: return t("Falta", "Missing")
            case let .short(have): return t("Tienes \(have) de \(requirement.quantity)", "\(have) of \(requirement.quantity)")
            case let .expiring(on): return t("Vence el \(on.formatted(date: .abbreviated, time: .omitted))", "Expires \(on.formatted(date: .abbreviated, time: .omitted))")
            case .expired: return t("Vencido", "Expired")
            }
        }

        public var summary: String {
            switch problem {
            case .missing: return t("Falta: \(requirement.label) ×\(toBuy)", "Missing: \(requirement.label) ×\(toBuy)")
            case let .short(have): return t("\(requirement.label): \(have) de \(requirement.quantity)", "\(requirement.label): \(have) of \(requirement.quantity)")
            case let .expiring(on): return t("\(requirement.label) vence el \(on.formatted(date: .abbreviated, time: .omitted))", "\(requirement.label) expires \(on.formatted(date: .abbreviated, time: .omitted))")
            case .expired: return t("\(requirement.label) vencido", "\(requirement.label) expired")
            }
        }
    }

    /// What this household's bag should contain.
    public static func recommended(for profile: AgentProfile) -> [Requirement] {
        let people = max(1, profile.housemates.count + 1)
        var list: [Requirement] = [
            Requirement(kind: .water, label: GoBagKind.water.displayName, quantity: people * 3 * 3, reason: t("3 L por persona al día, 3 días", "3 L per person per day, 3 days")),
            Requirement(kind: .food, label: GoBagKind.food.displayName, quantity: people * 3 * 2, reason: t("2 raciones por persona al día", "2 rations per person per day")),
            Requirement(kind: .flashlight, label: GoBagKind.flashlight.displayName, quantity: 1, reason: ""),
            Requirement(kind: .batteries, label: GoBagKind.batteries.displayName, quantity: 8, reason: t("Para linterna y radio", "For flashlight and radio")),
            Requirement(kind: .powerBank, label: GoBagKind.powerBank.displayName, quantity: 1, reason: t("El teléfono es tu canal con la familia", "Your phone is your line to family")),
            Requirement(kind: .radio, label: GoBagKind.radio.displayName, quantity: 1, reason: t("Avisos oficiales sin internet", "Official updates without internet")),
            Requirement(kind: .firstAidKit, label: GoBagKind.firstAidKit.displayName, quantity: 1, reason: ""),
            Requirement(kind: .whistle, label: GoBagKind.whistle.displayName, quantity: people, reason: t("Para que te encuentren bajo escombros", "So rescuers can find you")),
            Requirement(kind: .masks, label: GoBagKind.masks.displayName, quantity: people * 2, reason: t("Polvo y ceniza", "Dust and ash")),
            Requirement(kind: .blanket, label: GoBagKind.blanket.displayName, quantity: people, reason: ""),
            Requirement(kind: .hygiene, label: GoBagKind.hygiene.displayName, quantity: 1, reason: ""),
            Requirement(kind: .documents, label: GoBagKind.documents.displayName, quantity: 1, reason: t("Cédulas, seguros y recetas", "IDs, insurance and prescriptions")),
            Requirement(kind: .cash, label: GoBagKind.cash.displayName, quantity: 1, reason: t("Sin señal no hay pagos digitales", "No signal, no digital payments"))
        ]
        for member in profile.household {
            for medication in member.medical.medications {
                list.append(Requirement(
                    kind: .medication,
                    label: t("\(medication.name) (\(member.name))", "\(medication.name) (\(member.name))"),
                    quantity: 7,
                    reason: t("7 días de dosis", "7 days of doses") + (medication.needsRefrigeration ? t(", con bolsa fría", ", with a cold pack") : "")
                ))
            }
        }
        return list
    }

    /// Everything missing, short or expiring within `soon` days.
    public static func audit(_ bag: [GoBagItem], for profile: AgentProfile, now: Date, soon: Int = 30) -> [Gap] {
        recommended(for: profile).compactMap { requirement in
            let items = bag.filter { $0.kind == requirement.kind && (requirement.kind != .medication || $0.label == requirement.label) }
            let have = items.map(\.quantity).reduce(0, +)
            if have == 0 { return Gap(requirement: requirement, problem: .missing, toBuy: requirement.quantity) }

            if let earliest = items.compactMap(\.expiresAt).min() {
                if earliest <= now { return Gap(requirement: requirement, problem: .expired, toBuy: requirement.quantity) }
                if earliest <= now.addingTimeInterval(TimeInterval(soon) * 86_400) {
                    return Gap(requirement: requirement, problem: .expiring(on: earliest), toBuy: requirement.quantity)
                }
            }
            if have < requirement.quantity {
                return Gap(requirement: requirement, problem: .short(have: have), toBuy: requirement.quantity - have)
            }
            return nil
        }
    }

    /// Share of recommended items fully in place, 0–100.
    public static func readiness(_ bag: [GoBagItem], for profile: AgentProfile, now: Date) -> Int {
        let total = recommended(for: profile).count
        guard total > 0 else { return 100 }
        return (total - audit(bag, for: profile, now: now).count) * 100 / total
    }
}

/// An order the agent prepares; the person reviews and sends it themselves.
public struct SupplyOrder: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String
        public let name: String
        public let quantity: Int
        public let query: String
        public let isMedication: Bool
    }

    public let lines: [Line]

    public init(gaps: [GoBag.Gap]) {
        lines = gaps.compactMap { gap in
            guard gap.requirement.kind != .cash, gap.requirement.kind != .documents else { return nil }
            return Line(
                id: gap.id,
                name: gap.requirement.label,
                quantity: gap.toBuy,
                query: gap.requirement.kind.searchQuery.isEmpty ? gap.requirement.label : gap.requirement.kind.searchQuery,
                isMedication: gap.requirement.kind == .medication
            )
        }
    }

    /// A ready-to-send message for a neighborhood store or pharmacy.
    public func whatsAppMessage(customer: String, area: String, lines selected: [Line]? = nil) -> String {
        let items = (selected ?? lines).map { "• \($0.name) ×\($0.quantity)" }.joined(separator: "\n")
        return t("Hola, soy \(customer) de \(area). Quisiera pedir para mi mochila de emergencia:\n\(items)\n¿Me confirman disponibilidad, precio y entrega? Gracias.",
                 "Hi, this is \(customer) from \(area). I'd like to order for my emergency go-bag:\n\(items)\nCould you confirm availability, price and delivery? Thanks.")
    }

    /// Mercado Libre search for one line in the household's country.
    public static func marketplaceURL(for line: Line, country: Country) -> URL? {
        let domain: String
        switch country {
        case .colombia: domain = "listado.mercadolibre.com.co"
        case .peru: domain = "listado.mercadolibre.com.pe"
        case .mexico: domain = "listado.mercadolibre.com.mx"
        case .chile: domain = "listado.mercadolibre.cl"
        case .argentina: domain = "listado.mercadolibre.com.ar"
        case .venezuela: domain = "listado.mercadolibre.com.ve"
        case .ecuador: domain = "listado.mercadolibre.com.ec"
        case .unitedStates: return URL(string: "https://www.amazon.com/s?k=\(line.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        let slug = line.query.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
        return URL(string: "https://\(domain)/\(slug)")
    }
}
