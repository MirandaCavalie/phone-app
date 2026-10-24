import Foundation

public struct GeoPoint: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in kilometers (haversine).
    public func distanceKm(to other: GeoPoint) -> Double {
        let r = 6_371.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// An earthquake or tsunami alert from an official source, fetched by a phone that still
/// has internet and relayed over the mesh to phones that do not.
public struct HazardAlert: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case earthquake
        case tsunami
        case volcano
        case flood
        case cyclone
        case wildfire
        case drought

        public var displayName: String {
            switch self {
            case .earthquake: t("Sismo", "Earthquake")
            case .tsunami: "Tsunami"
            case .volcano: t("Volcán", "Volcano")
            case .flood: t("Inundación", "Flood")
            case .cyclone: t("Ciclón", "Cyclone")
            case .wildfire: t("Incendio forestal", "Wildfire")
            case .drought: t("Sequía", "Drought")
            }
        }

        public var systemImage: String {
            switch self {
            case .earthquake: "waveform.path.ecg"
            case .tsunami: "water.waves"
            case .volcano: "mountain.2.fill"
            case .flood: "cloud.heavyrain.fill"
            case .cyclone: "hurricane"
            case .wildfire: "flame.fill"
            case .drought: "sun.max.trianglebadge.exclamationmark"
            }
        }
    }

    /// Official alert level for non-seismic events (GDACS green/orange/red, PTWC category).
    public var alertLevel: String? { pagerLevel }

    /// Two sources reporting the same physical event (USGS and EMSC for one quake).
    public func isSameEvent(as other: HazardAlert) -> Bool {
        guard kind == other.kind || (kind == .earthquake && other.kind == .tsunami) || (kind == .tsunami && other.kind == .earthquake) else { return false }
        if eventID == other.eventID { return true }
        let window: TimeInterval = kind == .earthquake || kind == .tsunami ? 120 : 6 * 3_600
        let distance = kind == .earthquake || kind == .tsunami ? 100.0 : 50.0
        return abs(occurredAt.timeIntervalSince(other.occurredAt)) < window
            && epicenter.distanceKm(to: other.epicenter) < distance
            && (magnitude == 0 || other.magnitude == 0 || abs(magnitude - other.magnitude) < 0.8)
    }

    public let id: UUID
    /// The source's own event id (e.g. USGS "us6000u4n8"); several phones may relay the same event.
    public let eventID: String
    public let source: String
    public let kind: Kind
    public let magnitude: Double
    public let place: String
    public let epicenter: GeoPoint
    public let depthKm: Double
    public let occurredAt: Date
    /// USGS PAGER impact level: green, yellow, orange or red.
    public let pagerLevel: String?
    public let tsunamiFlag: Bool
    public let url: String
    /// The phone that fetched it; its signature covers this alert.
    public let relayedBy: String
    public let isSimulated: Bool

    public init(
        id: UUID = UUID(), eventID: String, source: String, kind: Kind, magnitude: Double, place: String,
        epicenter: GeoPoint, depthKm: Double, occurredAt: Date, pagerLevel: String?, tsunamiFlag: Bool,
        url: String, relayedBy: String, isSimulated: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.source = source
        self.kind = kind
        self.magnitude = magnitude
        self.place = place
        self.epicenter = epicenter
        self.depthKm = depthKm
        self.occurredAt = occurredAt
        self.pagerLevel = pagerLevel
        self.tsunamiFlag = tsunamiFlag
        self.url = url
        self.relayedBy = relayedBy
        self.isSimulated = isSimulated
    }
}

/// Parser for the USGS real-time GeoJSON feeds
/// (https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php). Free, no key.
public enum USGSFeed {
    public static let pastHour = URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson")!
    public static let significantPastDay = URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson")!

    private struct Collection: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let mag: Double?
                let place: String?
                let time: Double
                let tsunami: Int?
                let alert: String?
                let url: String?
                let type: String?
            }
            struct Geometry: Decodable {
                let coordinates: [Double]
            }
            let id: String
            let properties: Properties
            let geometry: Geometry
        }
        let features: [Feature]
    }

    public static func parse(_ data: Data, relayedBy: String) throws -> [HazardAlert] {
        try JSONDecoder().decode(Collection.self, from: data).features.compactMap { feature in
            let p = feature.properties
            let c = feature.geometry.coordinates
            guard let magnitude = p.mag, c.count >= 2, p.type == nil || p.type == "earthquake" else { return nil }
            let tsunami = (p.tsunami ?? 0) == 1
            return HazardAlert(
                eventID: feature.id,
                source: "USGS",
                kind: tsunami ? .tsunami : .earthquake,
                magnitude: magnitude,
                place: p.place ?? "Unknown location",
                epicenter: GeoPoint(latitude: c[1], longitude: c[0]),
                depthKm: c.count > 2 ? c[2] : 0,
                occurredAt: Date(timeIntervalSince1970: p.time / 1_000),
                pagerLevel: p.alert,
                tsunamiFlag: tsunami,
                url: p.url ?? "https://earthquake.usgs.gov",
                relayedBy: relayedBy
            )
        }
    }
}

public struct HazardAssessment: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case ignore = 0
        /// Worth knowing: check your kit.
        case watch
        /// Likely felt strongly where you live.
        case warning
        /// Act now: emergency mode starts before the network fails.
        case danger

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public let level: Level
    public let distanceKm: Double
    public let headline: String
    public let advice: String

    /// Floods, volcanoes, cyclones, wildfires and PTWC tsunami bulletins: graded by the
    /// source's own alert level and by distance.
    static func assessOther(_ alert: HazardAlert, distance d: Double) -> HazardAssessment {
        let km = Int(d.rounded())
        let level = (alert.pagerLevel ?? "").lowercased()
        let name = alert.kind.displayName

        if alert.kind == .tsunami {
            // PTWC categories: threat/warning/watch/advisory. "Information" never reaches here.
            let severe = ["threat", "warning"].contains(where: level.contains)
            guard d <= 3_000 else { return HazardAssessment(level: .ignore, distanceKm: d, headline: "", advice: "") }
            return HazardAssessment(
                level: severe ? .danger : .warning, distanceKm: d,
                headline: t("Boletín de tsunami (\(alert.pagerLevel ?? "PTWC")) a \(km) km", "Tsunami bulletin (\(alert.pagerLevel ?? "PTWC")) \(km) km away"),
                advice: t("Si estás en la costa, sube a una zona alta y sigue a las autoridades.", "If you are on the coast, move to high ground and follow local authorities.")
            )
        }

        let radius: Double
        let grade: Level
        switch level {
        case "red": radius = 500; grade = .danger
        case "orange": radius = 350; grade = .warning
        default: radius = 150; grade = .watch
        }
        guard d <= radius else { return HazardAssessment(level: .ignore, distanceKm: d, headline: "", advice: "") }

        let advice: String
        switch alert.kind {
        case .flood: advice = t("Aléjate de ríos y quebradas; no cruces calles inundadas.", "Stay away from rivers and ravines; never cross flooded streets.")
        case .volcano: advice = t("Sigue a las autoridades; protégete de la ceniza con mascarilla.", "Follow authorities; use a mask against ash.")
        case .cyclone: advice = t("Refúgiate lejos de ventanas y asegura agua y baterías.", "Shelter away from windows; secure water and batteries.")
        case .wildfire: advice = t("Prepárate para evacuar y evita el humo.", "Be ready to evacuate and avoid the smoke.")
        default: advice = t("Revisa tu kit y a tu familia.", "Check your kit and your family.")
        }
        return HazardAssessment(
            level: grade, distanceKm: d,
            headline: t("\(name) a \(km) km de ti", "\(name) \(km) km away"),
            advice: advice
        )
    }

    /// How far a quake of this size is typically felt strongly (rough, conservative).
    static func feltRadiusKm(_ magnitude: Double) -> Double {
        switch magnitude {
        case ..<5: 80
        case ..<6: 200
        case ..<7: 450
        case ..<8: 900
        default: 1_500
        }
    }

    public static func assess(_ alert: HazardAlert, home: GeoPoint?) -> HazardAssessment {
        guard let home else {
            return HazardAssessment(level: .ignore, distanceKm: .infinity, headline: "", advice: "")
        }
        let d = alert.epicenter.distanceKm(to: home)
        if alert.kind != .earthquake && !(alert.kind == .tsunami && alert.source != "PTWC") {
            return assessOther(alert, distance: d)
        }
        let felt = feltRadiusKm(alert.magnitude)
        let m = String(format: "%.1f", alert.magnitude)
        let km = Int(d.rounded())

        if alert.tsunamiFlag && alert.magnitude >= 7 && d <= 1_000 {
            return HazardAssessment(
                level: .danger, distanceKm: d,
                headline: t("Posible tsunami: sismo M\(m) a \(km) km", "Possible tsunami: M\(m) quake \(km) km away"),
                advice: t("Si estás cerca de la costa, sube a una zona alta ahora.", "If you are near the coast, move to high ground now.")
            )
        }
        if alert.magnitude >= 6.5 && d <= felt * 0.5 {
            return HazardAssessment(
                level: .danger, distanceKm: d,
                headline: t("Sismo fuerte M\(m) a \(km) km de ti", "Strong M\(m) quake \(km) km away"),
                advice: t("Agáchate, cúbrete y sujétate. Espera réplicas.", "Drop, cover and hold on. Expect aftershocks.")
            )
        }
        if alert.magnitude >= 5.5 && d <= felt {
            return HazardAssessment(
                level: .warning, distanceKm: d,
                headline: t("Sismo M\(m) a \(km) km de ti", "M\(m) quake \(km) km away"),
                advice: t("Revisa a tu familia y prepárate para réplicas.", "Check on your family and prepare for aftershocks.")
            )
        }
        if alert.magnitude >= 4.5 && d <= felt * 1.5 {
            return HazardAssessment(
                level: .watch, distanceKm: d,
                headline: t("Sismo M\(m) en tu región (\(km) km)", "M\(m) quake in your region (\(km) km)"),
                advice: t("Buen momento para revisar tu kit.", "Good time to check your kit.")
            )
        }
        return HazardAssessment(level: .ignore, distanceKm: d, headline: "", advice: "")
    }
}

/// Approximate coordinates for neighborhoods and cities, so the agent can measure
/// distance to an epicenter without asking for the person's exact location.
public enum Places {
    static let cities: [String: GeoPoint] = [
        "bogota": .init(latitude: 4.711, longitude: -74.072),
        "medellin": .init(latitude: 6.244, longitude: -75.581),
        "cali": .init(latitude: 3.452, longitude: -76.532),
        "barranquilla": .init(latitude: 10.964, longitude: -74.796),
        "cartagena": .init(latitude: 10.391, longitude: -75.479),
        "bucaramanga": .init(latitude: 7.119, longitude: -73.123),
        "pereira": .init(latitude: 4.813, longitude: -75.696),
        "caracas": .init(latitude: 10.480, longitude: -66.904),
        "maracaibo": .init(latitude: 10.654, longitude: -71.640),
        "valencia": .init(latitude: 10.162, longitude: -68.008),
        "barquisimeto": .init(latitude: 10.067, longitude: -69.347),
        "merida": .init(latitude: 8.589, longitude: -71.156),
        "ciudad de mexico": .init(latitude: 19.433, longitude: -99.133),
        "cdmx": .init(latitude: 19.433, longitude: -99.133),
        "guadalajara": .init(latitude: 20.659, longitude: -103.350),
        "oaxaca": .init(latitude: 17.073, longitude: -96.726),
        "acapulco": .init(latitude: 16.853, longitude: -99.823),
        "santiago": .init(latitude: -33.449, longitude: -70.669),
        "valparaiso": .init(latitude: -33.047, longitude: -71.613),
        "concepcion": .init(latitude: -36.827, longitude: -73.050),
        "lima": .init(latitude: -12.046, longitude: -77.043),
        "arequipa": .init(latitude: -16.409, longitude: -71.537),
        "quito": .init(latitude: -0.180, longitude: -78.468),
        "guayaquil": .init(latitude: -2.170, longitude: -79.922),
        "manta": .init(latitude: -0.967, longitude: -80.709),
        "buenos aires": .init(latitude: -34.604, longitude: -58.382),
        "mendoza": .init(latitude: -32.889, longitude: -68.845),
        "san francisco": .init(latitude: 37.774, longitude: -122.419)
    ]

    static let neighborhoods: [String: String] = [
        "chapinero": "bogota", "usaquen": "bogota", "suba": "bogota", "kennedy": "bogota", "bosa": "bogota",
        "teusaquillo": "bogota", "la candelaria": "bogota",
        "el poblado": "medellin", "laureles": "medellin", "belen": "medellin", "envigado": "medellin",
        "granada": "cali", "san antonio": "cali",
        "chacao": "caracas", "altamira": "caracas", "petare": "caracas", "catia": "caracas",
        "el hatillo": "caracas", "los palos grandes": "caracas",
        "roma norte": "ciudad de mexico", "condesa": "ciudad de mexico", "coyoacan": "ciudad de mexico",
        "iztapalapa": "ciudad de mexico", "providencia": "santiago", "nunoa": "santiago",
        "miraflores": "lima", "barranco": "lima", "la mariscal": "quito",
        "mission": "san francisco", "soma": "san francisco", "tenderloin": "san francisco",
        "chinatown": "san francisco", "sunset": "san francisco", "richmond": "san francisco",
        "castro": "san francisco", "marina": "san francisco", "bernal heights": "san francisco",
        "excelsior": "san francisco", "bayview": "san francisco", "potrero hill": "san francisco",
        "noe valley": "san francisco", "downtown": "san francisco"
    ]

    static let capitals: [Country: String] = [
        .colombia: "bogota", .venezuela: "caracas", .mexico: "ciudad de mexico", .chile: "santiago",
        .peru: "lima", .ecuador: "quito", .argentina: "buenos aires", .unitedStates: "san francisco"
    ]

    static let displayNames: [String: String] = [
        "bogota": "Bogotá", "medellin": "Medellín", "ciudad de mexico": "Ciudad de México", "cdmx": "Ciudad de México",
        "valparaiso": "Valparaíso", "concepcion": "Concepción", "merida": "Mérida", "san francisco": "San Francisco",
        "buenos aires": "Buenos Aires"
    ]

    static func name(_ key: String) -> String { displayNames[key] ?? key.capitalized }

    /// Best-effort location for an approximate area: neighborhood → city → country capital.
    public static func locate(area: String, country: Country) -> (point: GeoPoint, label: String) {
        let key = area.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let city = neighborhoods[key] ?? neighborhoods.first(where: { key.contains($0.key) })?.value,
           let point = cities[city] {
            return (point, name(city))
        }
        if let city = cities.keys.sorted().first(where: { key.contains($0) }), let point = cities[city] {
            return (point, name(city))
        }
        let capital = capitals[country] ?? "bogota"
        return (cities[capital]!, name(capital))
    }
}
