import XCTest
@testable import BarrioMeshCore

final class HazardAlertTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_860_000)

    /// Trimmed from the real USGS feed format.
    private let feed = #"""
    {"type":"FeatureCollection","metadata":{"title":"USGS All Earthquakes, Past Hour","count":3},
     "features":[
      {"type":"Feature","id":"us7000abcd","geometry":{"type":"Point","coordinates":[-73.95,4.55,12.0]},
       "properties":{"mag":7.1,"place":"20 km SE of Bogotá, Colombia","time":1792859800000,"tsunami":0,"alert":"orange","url":"https://earthquake.usgs.gov/earthquakes/eventpage/us7000abcd","type":"earthquake"}},
      {"type":"Feature","id":"us7000tsun","geometry":{"type":"Point","coordinates":[-80.3,-1.2,20.0]},
       "properties":{"mag":7.6,"place":"Off the coast of Ecuador","time":1792859900000,"tsunami":1,"alert":"red","url":"https://earthquake.usgs.gov/x","type":"earthquake"}},
      {"type":"Feature","id":"nc99","geometry":{"type":"Point","coordinates":[-122.8,38.8,2.0]},
       "properties":{"mag":null,"place":"The Geysers","time":1792859950000,"tsunami":0,"alert":null,"url":null,"type":"earthquake"}}
     ]}
    """#

    private func alert(_ magnitude: Double, at point: GeoPoint, tsunami: Bool = false, id: String = UUID().uuidString, by: String = "relay") -> HazardAlert {
        HazardAlert(eventID: id, source: "USGS", kind: tsunami ? .tsunami : .earthquake, magnitude: magnitude, place: "Test",
                    epicenter: point, depthKm: 10, occurredAt: now.addingTimeInterval(-60), pagerLevel: nil,
                    tsunamiFlag: tsunami, url: "https://usgs.gov", relayedBy: by)
    }

    func testParsesTheUSGSFeedAndSkipsEventsWithoutMagnitude() throws {
        let alerts = try USGSFeed.parse(Data(feed.utf8), relayedBy: "me")
        XCTAssertEqual(alerts.map(\.eventID), ["us7000abcd", "us7000tsun"])
        XCTAssertEqual(alerts[0].epicenter.latitude, 4.55)
        XCTAssertEqual(alerts[0].pagerLevel, "orange")
        XCTAssertEqual(alerts[1].kind, .tsunami)
        XCTAssertEqual(alerts[0].occurredAt.timeIntervalSince1970, 1_792_859_800)
    }

    func testDistanceIsRealistic() {
        let bogota = Places.locate(area: "Chapinero", country: .colombia).point
        let medellin = Places.locate(area: "El Poblado", country: .colombia).point
        XCTAssertEqual(bogota.distanceKm(to: medellin), 240, accuracy: 15)
    }

    func testPlacesFallBackFromNeighborhoodToCityToCapital() {
        XCTAssertEqual(Places.locate(area: "Chacao", country: .venezuela).label, "Caracas")
        XCTAssertEqual(Places.locate(area: "cerca de Guayaquil centro", country: .ecuador).label, "Guayaquil")
        XCTAssertEqual(Places.locate(area: "Barrio desconocido", country: .peru).label, "Lima")
    }

    func testAssessmentLevels() {
        let bogota = Places.locate(area: "Chapinero", country: .colombia).point
        XCTAssertEqual(HazardAssessment.assess(alert(7.1, at: .init(latitude: 4.55, longitude: -73.95)), home: bogota).level, .danger)
        XCTAssertEqual(HazardAssessment.assess(alert(5.8, at: .init(latitude: 5.5, longitude: -74.5)), home: bogota).level, .warning)
        XCTAssertEqual(HazardAssessment.assess(alert(4.6, at: .init(latitude: 5.0, longitude: -74.2)), home: bogota).level, .watch)
        XCTAssertEqual(HazardAssessment.assess(alert(6.0, at: .init(latitude: -14.2, longitude: 165.9)), home: bogota).level, .ignore, "Vanuatu")
    }

    func testTsunamiNearTheCoastIsDanger() {
        let guayaquil = Places.locate(area: "Guayaquil", country: .ecuador).point
        let result = HazardAssessment.assess(alert(7.6, at: .init(latitude: -1.2, longitude: -80.3), tsunami: true), home: guayaquil)
        XCTAssertEqual(result.level, .danger)
        XCTAssertTrue(result.headline.contains("tsunami"))
        XCTAssertTrue(result.advice.contains("zona alta"))
    }

    func testDangerousAlertActivatesTheAgentBeforeTheNetworkFails() {
        let agent = PersonalAgent(selfID: "me", profile: AgentProfile(name: "Ana", homeArea: "Chapinero"), policy: AgentPolicy())
        let quake = alert(7.1, at: .init(latitude: 4.55, longitude: -73.95), id: "us7000abcd")
        let result = agent.step(state: MeshState(hazardAlerts: [quake]), memory: AgentMemory(), connectivity: .online, now: now)

        XCTAssertTrue(result.memory.emergencyActive)
        XCTAssertTrue(result.memory.log.contains { $0.kind == .alert && $0.title.contains("M7.1") })
        XCTAssertTrue(result.memory.log.contains { $0.kind == .mode && $0.detail.contains("Alerta oficial") })

        // The same event relayed again by another phone is not handled twice.
        let copy = alert(7.1, at: .init(latitude: 4.55, longitude: -73.95), id: "us7000abcd", by: "other")
        let again = agent.step(state: MeshState(hazardAlerts: [copy]), memory: result.memory, connectivity: .online, now: now)
        XCTAssertEqual(again.memory.log.filter { $0.kind == .alert }.count, 1)
    }

    func testFarAwayAndOldAlertsAreIgnored() {
        let agent = PersonalAgent(selfID: "me", profile: AgentProfile(name: "Ana", homeArea: "Chapinero"), policy: AgentPolicy())
        let far = alert(6.5, at: .init(latitude: -14.2, longitude: 165.9))
        var old = alert(7.5, at: .init(latitude: 4.55, longitude: -73.95))
        old = HazardAlert(eventID: "old", source: "USGS", kind: .earthquake, magnitude: 7.5, place: "x", epicenter: old.epicenter,
                          depthKm: 10, occurredAt: now.addingTimeInterval(-86_400), pagerLevel: nil, tsunamiFlag: false, url: "", relayedBy: "r")
        let result = agent.step(state: MeshState(hazardAlerts: [far, old]), memory: AgentMemory(), connectivity: .online, now: now)
        XCTAssertFalse(result.memory.emergencyActive)
        XCTAssertFalse(result.memory.log.contains { $0.kind == .alert })
    }

    func testAlertsRelayOverTheMeshSignedOnceByEvent() {
        let online = AgentIdentity()
        let quake = alert(7.1, at: .init(latitude: 4.55, longitude: -73.95), id: "evt-1", by: online.agentID)
        var state = MeshState(hazardAlerts: [quake])
        state.signatures = MeshSecurity.sign(state, authorID: online.agentID, with: online)

        let offlinePhone = MeshStore()
        let verdict = MeshSecurity.verify(state, known: offlinePhone.state)
        XCTAssertEqual(verdict.accepted.hazardAlerts.count, 1)
        XCTAssertTrue(offlinePhone.merge(verdict.accepted, now: now))

        // A forged copy claiming another relayer's id is rejected.
        let impostor = AgentIdentity()
        var forged = MeshState(hazardAlerts: [alert(9.0, at: quake.epicenter, id: "evt-2", by: online.agentID)])
        forged.signatures = MeshSecurity.sign(forged, authorID: online.agentID, with: impostor)
        XCTAssertTrue(MeshSecurity.verify(forged, known: offlinePhone.state).accepted.hazardAlerts.isEmpty)

        // The same event from a second relayer does not duplicate.
        XCTAssertFalse(offlinePhone.merge(MeshState(hazardAlerts: [alert(7.1, at: quake.epicenter, id: "evt-1", by: "x")]), now: now))
    }

    func testOlderMemoryAndPolicyFilesStillLoad() throws {
        let memory = try JSONDecoder().decode(AgentMemory.self, from: Data(#"{"emergencyActive":true}"#.utf8))
        XCTAssertTrue(memory.emergencyActive)
        XCTAssertTrue(memory.seenHazards.isEmpty)
        let policy = try JSONDecoder().decode(AgentPolicy.self, from: Data("{}".utf8))
        XCTAssertTrue(policy.activateOnOfficialAlert)
    }

    func testCityNamesKeepTheirAccents() {
        XCTAssertEqual(Places.locate(area: "Chapinero", country: .colombia).label, "Bogotá")
        XCTAssertEqual(Places.locate(area: "Condesa", country: .mexico).label, "Ciudad de México")
    }

    /// Hits the real feed; run with `FARO_LIVE=1 swift test --filter testLiveUSGSFeedParses`.
    func testLiveUSGSFeedParses() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FARO_LIVE"] == "1", "network test")
        let data = try Data(contentsOf: USGSFeed.significantPastDay)
        let alerts = try USGSFeed.parse(data, relayedBy: "live")
        XCTAssertFalse(alerts.isEmpty)
        print("Live USGS: \(alerts.count) events, latest: M\(alerts[0].magnitude) \(alerts[0].place)")
    }
}
