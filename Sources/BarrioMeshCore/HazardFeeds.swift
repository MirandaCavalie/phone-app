import Foundation

/// Official and scientific real-time sources, all free and keyless, verified 2026-10-24.
/// Peru and Colombia publish no machine-readable national multi-hazard feed, so these
/// international sources (which include national agencies' data) cover both countries.
public enum HazardSource: String, CaseIterable, Codable, Sendable {
    case usgs = "USGS"
    case emsc = "EMSC"
    case gdacs = "GDACS"
    case ptwc = "PTWC"

    public var displayName: String {
        switch self {
        case .usgs: t("USGS · sismos", "USGS · earthquakes")
        case .emsc: t("EMSC · sismos de la región", "EMSC · regional earthquakes")
        case .gdacs: t("GDACS · inundaciones, volcanes, ciclones", "GDACS · floods, volcanoes, cyclones")
        case .ptwc: t("NOAA PTWC · tsunamis del Pacífico", "NOAA PTWC · Pacific tsunamis")
        }
    }

    /// Seconds between polls; heavier feeds are polled less often.
    public var pollInterval: TimeInterval {
        switch self {
        case .usgs, .emsc: 60
        case .ptwc: 120
        case .gdacs: 300
        }
    }

    public func url(around home: GeoPoint) -> URL {
        switch self {
        case .usgs:
            return USGSFeed.pastHour
        case .emsc:
            // A box of about ±12° around home covers every quake that could be felt there.
            let q = String(
                format: "format=json&orderby=time&limit=60&minmagnitude=3.5&minlatitude=%.1f&maxlatitude=%.1f&minlongitude=%.1f&maxlongitude=%.1f",
                home.latitude - 12, home.latitude + 12, home.longitude - 12, home.longitude + 12
            )
            return URL(string: "https://www.seismicportal.eu/fdsnws/event/1/query?\(q)")!
        case .gdacs:
            return URL(string: "https://www.gdacs.org/gdacsapi/api/events/geteventlist/EVENTS4APP")!
        case .ptwc:
            return URL(string: "https://www.tsunami.gov/events/xml/PHEBAtom.xml")!
        }
    }

    public func parse(_ data: Data, relayedBy: String) throws -> [HazardAlert] {
        switch self {
        case .usgs: try USGSFeed.parse(data, relayedBy: relayedBy)
        case .emsc: try EMSCFeed.parse(data, relayedBy: relayedBy)
        case .gdacs: try GDACSFeed.parse(data, relayedBy: relayedBy)
        case .ptwc: PTWCFeed.parse(data, relayedBy: relayedBy)
        }
    }
}

/// EMSC SeismicPortal FDSN event service (CC BY 4.0). Aggregates national networks,
/// including Colombia's and Ecuador's, typically within ~10 minutes.
public enum EMSCFeed {
    private struct Collection: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let time: String
                let mag: Double?
                let depth: Double?
                let flynn_region: String?
                let auth: String?
            }
            struct Geometry: Decodable { let coordinates: [Double] }
            let id: String
            let properties: Properties
            let geometry: Geometry
        }
        let features: [Feature]
    }

    public static func parse(_ data: Data, relayedBy: String) throws -> [HazardAlert] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return try JSONDecoder().decode(Collection.self, from: data).features.compactMap { feature in
            let p = feature.properties
            let c = feature.geometry.coordinates
            guard let magnitude = p.mag, c.count >= 2,
                  let time = iso.date(from: p.time) ?? plain.date(from: p.time) else { return nil }
            let region = (p.flynn_region ?? "").capitalized
            return HazardAlert(
                eventID: "emsc-\(feature.id)",
                source: "EMSC",
                kind: .earthquake,
                magnitude: magnitude,
                place: p.auth.map { "\(region) (\($0))" } ?? region,
                epicenter: GeoPoint(latitude: c[1], longitude: c[0]),
                depthKm: p.depth ?? (c.count > 2 ? abs(c[2]) : 0),
                occurredAt: time,
                pagerLevel: nil,
                tsunamiFlag: false,
                url: "https://www.seismicportal.eu/eventdetails.html?unid=\(feature.id)",
                relayedBy: relayedBy
            )
        }
    }
}

/// GDACS (UN/EC Global Disaster Alert and Coordination System). Floods, volcanoes,
/// tropical cyclones, wildfires and droughts with a green/orange/red alert level.
public enum GDACSFeed {
    private struct Collection: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                struct Severity: Decodable { let severity: Double?; let severitytext: String? }
                struct Links: Decodable { let report: String? }
                let eventtype: String
                let eventid: Int
                let episodeid: Int?
                let name: String?
                let alertlevel: String?
                let iso3: String?
                let fromdate: String
                let severitydata: Severity?
                let url: Links?
            }
            struct Geometry: Decodable {
                let type: String
                let coordinates: [Double]?
            }
            let properties: Properties
            let geometry: Geometry?
        }
        let features: [Feature]
    }

    static func kind(_ code: String) -> HazardAlert.Kind? {
        switch code {
        case "FL": .flood
        case "VO": .volcano
        case "TC": .cyclone
        case "WF": .wildfire
        case "DR": .drought
        case "TS": .tsunami
        default: nil  // Earthquakes come faster from USGS and EMSC.
        }
    }

    public static func parse(_ data: Data, relayedBy: String) throws -> [HazardAlert] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return try JSONDecoder().decode(Collection.self, from: data).features.compactMap { feature in
            let p = feature.properties
            guard let kind = kind(p.eventtype),
                  let c = feature.geometry?.coordinates, c.count >= 2,
                  let date = formatter.date(from: String(p.fromdate.prefix(19))) else { return nil }
            return HazardAlert(
                eventID: "gdacs-\(p.eventtype)-\(p.eventid)",
                source: "GDACS",
                kind: kind,
                magnitude: kind == .tsunami ? (p.severitydata?.severity ?? 0) : 0,
                place: [p.name, p.severitydata?.severitytext].compactMap { $0 }.joined(separator: " · "),
                epicenter: GeoPoint(latitude: c[1], longitude: c[0]),
                depthKm: 0,
                occurredAt: date,
                pagerLevel: p.alertlevel?.lowercased(),
                tsunamiFlag: kind == .tsunami,
                url: p.url?.report ?? "https://www.gdacs.org",
                relayedBy: relayedBy
            )
        }
    }
}

/// NOAA Pacific Tsunami Warning Center Atom feed. Only real threats become alerts;
/// "Information" statements (no tsunami expected) are dropped.
public enum PTWCFeed {
    public static func parse(_ data: Data, relayedBy: String) -> [HazardAlert] {
        let parser = AtomEntries(data: data)
        let iso = ISO8601DateFormatter()
        return parser.entries.compactMap { entry in
            guard let lat = Double(entry["geo:lat"] ?? ""), let lon = Double(entry["geo:long"] ?? ""),
                  let updated = entry["updated"].flatMap(iso.date(from:)) else { return nil }
            let summary = entry["summary"] ?? ""
            let category = field("Category:", in: summary) ?? ""
            guard !category.lowercased().contains("information"), !category.isEmpty else { return nil }
            let magnitude = field("Preliminary Magnitude:", in: summary)
                .flatMap { Double($0.prefix(while: { $0.isNumber || $0 == "." })) } ?? 0
            return HazardAlert(
                eventID: "ptwc-\(entry["id"] ?? "\(lat),\(lon),\(updated.timeIntervalSince1970)")",
                source: "PTWC",
                kind: .tsunami,
                magnitude: magnitude,
                place: entry["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Pacific",
                epicenter: GeoPoint(latitude: lat, longitude: lon),
                depthKm: 0,
                occurredAt: updated,
                pagerLevel: category,
                tsunamiFlag: true,
                url: entry["link"] ?? "https://www.tsunami.gov",
                relayedBy: relayedBy
            )
        }
    }

    /// Value after a bold label in the PTWC xhtml summary, e.g. "Category: Warning".
    static func field(_ label: String, in summary: String) -> String? {
        let text = summary.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        guard let range = text.range(of: label) else { return nil }
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let value = rest.prefix(while: { $0 != "\n" }).components(separatedBy: "  ").first ?? ""
        return value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value.trimmingCharacters(in: .whitespaces)
    }
}

/// Minimal Atom reader: collects child element text per <entry>, plus the bulletin link.
final class AtomEntries: NSObject, XMLParserDelegate {
    private(set) var entries: [[String: String]] = []
    private var current: [String: String]?
    private var text = ""
    private var depthInSummary = 0

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "entry" { current = [:]; return }
        guard current != nil else { return }
        if depthInSummary > 0 { depthInSummary += 1; text += "<\(name)>"; return }
        if name == "summary" { depthInSummary = 1; text = ""; return }
        if name == "link", attributes["title"] == "Bulletin", let href = attributes["href"] { current?["link"] = href }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "entry", let entry = current { entries.append(entry); current = nil; return }
        guard current != nil else { return }
        if depthInSummary > 0 {
            depthInSummary -= 1
            if depthInSummary == 0 { current?["summary"] = text } else { text += "</\(name)>" }
            return
        }
        // <link> carries its value in attributes, read when the element started.
        guard name != "link" else { return }
        current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
