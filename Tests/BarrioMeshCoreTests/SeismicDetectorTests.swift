import XCTest
@testable import BarrioMeshCore

final class SeismicDetectorTests: XCTestCase {
    private let rate = 50.0

    /// Runs `seconds` of samples through the detector and returns the first event.
    private func run(_ detector: inout SeismicDetector, from start: Double, seconds: Double, amplitude: (Double) -> Double) -> SeismicEvent? {
        var event: SeismicEvent?
        var t = start
        while t < start + seconds {
            let a = amplitude(t)
            if let detected = detector.ingest(time: t, x: a * sin(t * 37), y: a * cos(t * 23), z: a * 0.5) , event == nil {
                event = detected
            }
            t += 1 / rate
        }
        return event
    }

    private func quietNoise(_ t: Double) -> Double { 0.004 + 0.002 * sin(t * 3) }

    func testSustainedShakingAfterQuietTriggers() {
        var detector = SeismicDetector()
        XCTAssertNil(run(&detector, from: 0, seconds: 10, amplitude: quietNoise))
        let event = run(&detector, from: 10, seconds: 4, amplitude: { _ in 0.25 })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.intensity, .severe)
        XCTAssertGreaterThanOrEqual(event?.duration ?? 0, 1.2)
    }

    func testSingleBumpDoesNotTrigger() {
        var detector = SeismicDetector()
        _ = run(&detector, from: 0, seconds: 10, amplitude: quietNoise)
        let event = run(&detector, from: 10, seconds: 4, amplitude: { t in (10.0...10.3).contains(t) ? 0.6 : 0.004 })
        XCTAssertNil(event)
    }

    func testQuietPhoneNeverTriggers() {
        var detector = SeismicDetector()
        XCTAssertNil(run(&detector, from: 0, seconds: 60, amplitude: quietNoise))
    }

    func testCooldownPreventsRepeatedEvents() {
        var detector = SeismicDetector()
        _ = run(&detector, from: 0, seconds: 10, amplitude: quietNoise)
        XCTAssertNotNil(run(&detector, from: 10, seconds: 4, amplitude: { _ in 0.2 }))
        _ = run(&detector, from: 14, seconds: 10, amplitude: quietNoise)
        XCTAssertNil(run(&detector, from: 24, seconds: 4, amplitude: { _ in 0.2 }), "within the 60 s cooldown")
    }

    func testIntensityScale() {
        XCTAssertEqual(SeismicEvent(peakAcceleration: 0.02, duration: 2).intensity, .light)
        XCTAssertEqual(SeismicEvent(peakAcceleration: 0.05, duration: 2).intensity, .moderate)
        XCTAssertEqual(SeismicEvent(peakAcceleration: 0.1, duration: 2).intensity, .strong)
    }

    func testAgentCountsDownAloneButActsAtOnceWhenNeighborsFeltIt() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let agent = PersonalAgent(selfID: "ana", profile: AgentProfile(name: "Ana", homeArea: "Chacao"), policy: AgentPolicy())
        let event = SeismicEvent(peakAcceleration: 0.2, duration: 2)
        let mine = SeismicReport(deviceID: "ana", area: "Chacao", peakAcceleration: 0.2, detectedAt: now)
        let neighbor = SeismicReport(deviceID: "luis", area: "Chacao", peakAcceleration: 0.15, detectedAt: now.addingTimeInterval(-10))

        XCTAssertEqual(agent.assessShaking(event, reports: [mine], memory: AgentMemory(), now: now), .countdown(seconds: 15))
        XCTAssertEqual(agent.assessShaking(event, reports: [mine, neighbor], memory: AgentMemory(), now: now), .activateNow(phones: 2))

        var off = AgentPolicy()
        off.activateOnShaking = false
        let disabled = PersonalAgent(selfID: "ana", profile: agent.profile, policy: off)
        XCTAssertEqual(disabled.assessShaking(event, reports: [mine, neighbor], memory: AgentMemory(), now: now), .ignore)
    }

    func testTwoNeighborReportsActivateAPhoneThatFeltNothing() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let agent = PersonalAgent(selfID: "ana", profile: AgentProfile(name: "Ana", homeArea: "Chacao"), policy: AgentPolicy())
        let reports = [
            SeismicReport(deviceID: "luis", area: "Chacao", peakAcceleration: 0.15, detectedAt: now.addingTimeInterval(-5)),
            SeismicReport(deviceID: "marta", area: "Chacao", peakAcceleration: 0.12, detectedAt: now.addingTimeInterval(-3))
        ]
        let one = agent.step(state: MeshState(seismicReports: [reports[0]]), memory: AgentMemory(), connectivity: .online, now: now)
        XCTAssertFalse(one.memory.emergencyActive)

        let two = agent.step(state: MeshState(seismicReports: reports), memory: AgentMemory(), connectivity: .online, now: now)
        XCTAssertTrue(two.memory.emergencyActive)
        XCTAssertTrue(two.memory.log.contains { $0.detail.contains("2 teléfonos") })

        let stale = agent.step(state: MeshState(seismicReports: reports), memory: AgentMemory(), connectivity: .online, now: now.addingTimeInterval(600))
        XCTAssertFalse(stale.memory.emergencyActive, "old reports do not re-trigger")
    }

    func testOldPolicyFilesGainTheNewPermission() throws {
        let json = #"{"activateOnOutage":false,"autoCheckIn":true,"autoPublishNeeds":true,"autoPublishOffers":true,"autoAcceptIncomingHelp":true,"autoGiveLimit":2}"#
        let policy = try JSONDecoder().decode(AgentPolicy.self, from: Data(json.utf8))
        XCTAssertFalse(policy.activateOnOutage)
        XCTAssertTrue(policy.activateOnShaking)
        XCTAssertEqual(policy.autoGiveLimit, 2)
    }
}
