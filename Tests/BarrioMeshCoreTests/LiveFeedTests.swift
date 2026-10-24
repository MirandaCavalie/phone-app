import XCTest
@testable import BarrioMeshCore

/// Fixtures are trimmed copies of real responses fetched on 2026-10-24.
final class LiveFeedTests: XCTestCase {
    private let emsc = #"""
    {"type":"FeatureCollection","metadata":{"count":2},"features":[
     {"geometry":{"type":"Point","coordinates":[-80.45,-4.06,-36.0]},"type":"Feature","id":"20261024_0000378",
      "properties":{"lastupdate":"2026-10-24T21:05:00.0Z","magtype":"m","evtype":"ke","lon":-80.45,"auth":"QUI","lat":-4.06,"depth":36.0,"unid":"20261024_0000378","mag":4.4,"time":"2026-10-24T20:57:05.2Z","source_id":"1","source_catalog":"EMSC-RTS","flynn_region":"PERU-ECUADOR BORDER REGION"}},
     {"geometry":{"type":"Point","coordinates":[-80.2853,7.4282,-4.0]},"type":"Feature","id":"20261024_0000379",
      "properties":{"magtype":"ml","auth":"IGC","depth":4.0,"mag":3.5,"time":"2026-10-24T21:00:44.0Z","flynn_region":"PANAMA"}}
    ]}
    """#

    private let gdacs = #"""
    {"type":"FeatureCollection","features":[
     {"type":"Feature","geometry":{"type":"Point","coordinates":[-75.6,4.8]},
      "properties":{"eventtype":"FL","eventid":1103001,"episodeid":3,"name":"Flood in Colombia","alertlevel":"Orange","iso3":"COL","fromdate":"2026-10-22T00:00:00","severitydata":{"severity":0,"severitytext":"Magnitude 0 "},"url":{"report":"https://www.gdacs.org/report.aspx?eventid=1103001&episodeid=3&eventtype=FL"}}},
     {"type":"Feature","geometry":{"type":"Point","coordinates":[159.1963,52.1565]},
      "properties":{"eventtype":"EQ","eventid":1573671,"name":"Earthquake in Russia","alertlevel":"Green","iso3":"RUS","fromdate":"2026-10-24T20:35:04","severitydata":{"severity":5.3,"severitytext":"Magnitude 5.3M"}}},
     {"type":"Feature","geometry":{"type":"Point","coordinates":[-75.3,4.9]},
      "properties":{"eventtype":"VO","eventid":3001,"name":"Nevado del Ruiz","alertlevel":"Green","iso3":"COL","fromdate":"2026-10-20T00:00:00"}}
    ]}
    """#

    private let ptwc = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:geo="http://www.w3.org/2003/01/geo/wgs84_pos#">
    <title>  TSUNAMI MESSAGE NUMBER 1  </title><updated>2026-10-24T03:30:54Z</updated>
    <entry>
     <title>off the coast of central Peru</title><updated>2026-10-24T03:20:00Z</updated>
     <geo:lat>-12.500</geo:lat><geo:long>-77.800</geo:long>
     <summary type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><strong>Category:</strong> Threat<br/><strong>Preliminary Magnitude: </strong>8.1(Mwp)<br/></div></summary>
     <id>urn:uuid:aaaa</id><link rel="alternate" title="Bulletin" href="https://www.tsunami.gov/x.txt" type="application/xml" />
    </entry>
    <entry>
     <title>near the Vanuatu Islands</title><updated>2026-10-24T02:39:49Z</updated>
     <geo:lat>-13.800</geo:lat><geo:long>165.700</geo:long>
     <summary type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><strong>Category:</strong> Information<br/><strong>Preliminary Magnitude: </strong>7.2(Mwp)<br/></div></summary>
     <id>urn:uuid:bbbb</id>
    </entry>
    </feed>
    """#

    private let lima = Places.locate(area: "Miraflores", country: .peru).point
    private let pereira = Places.locate(area: "Pereira", country: .colombia).point

    func testEMSCParsesRegionalQuakes() throws {
        let alerts = try EMSCFeed.parse(Data(emsc.utf8), relayedBy: "me")
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts[0].magnitude, 4.4)
        XCTAssertEqual(alerts[0].epicenter.latitude, -4.06)
        XCTAssertEqual(alerts[0].depthKm, 36)
        XCTAssertTrue(alerts[0].place.contains("Peru-Ecuador"))
        XCTAssertEqual(alerts[0].occurredAt.timeIntervalSince1970, 1_792_875_425.2, accuracy: 1)
    }

    func testGDACSKeepsFloodsAndVolcanoesAndLeavesQuakesToFasterFeeds() throws {
        let alerts = try GDACSFeed.parse(Data(gdacs.utf8), relayedBy: "me")
        XCTAssertEqual(alerts.map(\.kind), [.flood, .volcano])
        XCTAssertEqual(alerts[0].pagerLevel, "orange")
        let flood = HazardAssessment.assess(alerts[0], home: pereira)
        XCTAssertEqual(flood.level, .warning)
        XCTAssertTrue(flood.advice.contains("ríos"))
    }

    func testPTWCKeepsThreatsAndDropsInformationStatements() {
        let alerts = PTWCFeed.parse(Data(ptwc.utf8), relayedBy: "me")
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].kind, .tsunami)
        XCTAssertEqual(alerts[0].magnitude, 8.1)
        XCTAssertEqual(alerts[0].pagerLevel, "Threat")
        XCTAssertEqual(alerts[0].url, "https://www.tsunami.gov/x.txt")
        XCTAssertEqual(HazardAssessment.assess(alerts[0], home: lima).level, .danger)
    }

    func testSameQuakeFromTwoSourcesIsStoredOnce() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let usgs = HazardAlert(eventID: "us1", source: "USGS", kind: .earthquake, magnitude: 6.8, place: "Peru", epicenter: .init(latitude: -12.1, longitude: -77.2), depthKm: 30, occurredAt: date, pagerLevel: nil, tsunamiFlag: false, url: "", relayedBy: "a")
        let emsc = HazardAlert(eventID: "emsc-1", source: "EMSC", kind: .earthquake, magnitude: 6.6, place: "Near coast of Peru", epicenter: .init(latitude: -12.3, longitude: -77.0), depthKm: 28, occurredAt: date.addingTimeInterval(20), pagerLevel: nil, tsunamiFlag: false, url: "", relayedBy: "b")
        let other = HazardAlert(eventID: "emsc-2", source: "EMSC", kind: .earthquake, magnitude: 4.0, place: "Colombia", epicenter: .init(latitude: 4.5, longitude: -74), depthKm: 10, occurredAt: date, pagerLevel: nil, tsunamiFlag: false, url: "", relayedBy: "b")
        XCTAssertTrue(usgs.isSameEvent(as: emsc))
        XCTAssertFalse(usgs.isSameEvent(as: other))

        let store = MeshStore()
        store.add([usgs, emsc, other])
        XCTAssertEqual(store.state.hazardAlerts.map(\.eventID), ["us1", "emsc-2"])
    }

    func testSourcesBuildRegionalURLs() {
        let url = HazardSource.emsc.url(around: lima).absoluteString
        XCTAssertTrue(url.contains("minlatitude=-24.0"))
        XCTAssertTrue(url.contains("maxlongitude=-65.0"))
        XCTAssertEqual(Country.peru.iso3, "PER")
    }

    /// Opt-in: `FARO_LIVE=1 swift test --filter testLiveFeedsParse`.
    func testLiveFeedsParse() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FARO_LIVE"] == "1", "network test")
        for source in HazardSource.allCases {
            let data = try Data(contentsOf: source.url(around: lima))
            let alerts = try source.parse(data, relayedBy: "live")
            print("Live \(source.rawValue): \(alerts.count) alerts" + (alerts.first.map { ", first: \($0.kind.rawValue) \($0.place)" } ?? ""))
        }
    }
}
