import XCTest
@testable import BarrioMeshCore

final class PaperworkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private var profile: AgentProfile {
        AgentProfile(
            name: "Miranda", country: .colombia, homeArea: "Chapinero", meetingPoint: "Parque de la 93",
            household: [HouseholdMember(name: "Rosa", relation: "mamá", dependsOn: [.medicine])],
            familyContacts: [FamilyContact(name: "Tío Juan", phone: "573001234567")]
        )
    }

    private func scenario() -> (MeshState, AgentMemory) {
        let need = MeshPost(authorID: "me", authorName: "Miranda", kind: .need, resource: .water, quantity: 4, unit: "botellas",
                            urgency: .urgent, area: "Chapinero", note: "", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
        let offer = MeshPost(authorID: "luis", authorName: "Luis", kind: .offer, resource: .water, quantity: 3, unit: "botellas",
                             urgency: .normal, area: "Chapinero", note: "", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
        let proposal = MatchProposal(needID: need.id, offerID: offer.id)
        let ask = AgentMessage(proposalID: proposal.id, senderID: "me", senderName: "Miranda", kind: .propose,
                               terms: MeetingTerms(quantity: 3, meetingPoint: "Parque", meetAt: now), rationale: "", sentAt: now)
        let yes = AgentMessage(proposalID: proposal.id, senderID: "luis", senderName: "Luis", kind: .accept,
                               terms: ask.terms, respondsTo: ask.id, rationale: "", sentAt: now)
        let state = MeshState(
            posts: [need, offer], proposals: [proposal], messages: [ask, yes],
            seismicReports: [
                SeismicReport(deviceID: "me", area: "Chapinero", peakAcceleration: 0.21, detectedAt: now),
                SeismicReport(deviceID: "luis", area: "Chapinero", peakAcceleration: 0.18, detectedAt: now)
            ]
        )
        let agent = PersonalAgent(selfID: "me", profile: profile, policy: AgentPolicy())
        let memory = agent.activateForEarthquake(SeismicEvent(peakAcceleration: 0.21, duration: 3), phones: 2, memory: AgentMemory(), now: now)
        return (state, memory)
    }

    func testCallScriptNamesTheVulnerableAndWhatIsMissing() {
        let (state, _) = scenario()
        let script = Paperwork.callScript(profile: profile, state: state, selfID: "me", now: now)
        XCTAssertEqual(script.number, "123")
        XCTAssertTrue(script.text.contains("Chapinero"))
        XCTAssertTrue(script.text.contains("Rosa, depende de medicamentos"))
        XCTAssertTrue(script.text.contains("1 botella de agua"), "4 needed, 3 agreed")
    }

    func testReportIsPrefilledFromWhatTheAgentKnows() {
        let (state, memory) = scenario()
        let report = Paperwork.report(profile: profile, memory: memory, state: state, selfID: "me", now: now)
        let text = report.plainText

        XCTAssertTrue(text.contains("HOGAR (2 PERSONAS)"))
        XCTAssertTrue(text.contains("Rosa, mamá — depende de medicamentos"))
        XCTAssertTrue(text.contains("Teléfonos cercanos que sintieron el movimiento: 2"))
        XCTAssertTrue(text.contains("Recibimos 3 botellas de agua de Luis — acordado"))
        XCTAssertTrue(text.contains("1 botella de agua"))
        XCTAssertFalse(text.contains("calle"), "never an exact address")
    }

    func testUnitsAgreeWithQuantity() {
        XCTAssertEqual(Paperwork.quantity(1, "botellas"), "1 botella")
        XCTAssertEqual(Paperwork.quantity(1, "lugares"), "1 lugar")
        XCTAssertEqual(Paperwork.quantity(1, "cargas"), "1 carga")
        XCTAssertEqual(Paperwork.quantity(1, "kit"), "1 kit")
        XCTAssertEqual(Paperwork.quantity(2, "botellas"), "2 botellas")
    }
}
