import XCTest
@testable import BarrioMeshCore

final class OfflineAgentTests: XCTestCase {
    func testUnderstandsUrgentSpanishNeed() {
        let draft = OfflineAgent.interpret("Necesito 2 botellas de agua en Mission, es urgente")

        XCTAssertEqual(draft.kind, .need)
        XCTAssertEqual(draft.resource, .water)
        XCTAssertEqual(draft.quantity, 2)
        XCTAssertEqual(draft.urgency, .urgent)
        XCTAssertEqual(draft.area, "Mission")
        XCTAssertTrue(draft.isReady)
    }

    func testUnderstandsPowerOffer() {
        let draft = OfflineAgent.interpret("Tengo un power bank disponible en SOMA")

        XCTAssertEqual(draft.kind, .offer)
        XCTAssertEqual(draft.resource, .power)
        XCTAssertEqual(draft.quantity, 1)
        XCTAssertEqual(draft.area, "SOMA")
    }

    func testRecognizesMedicineWithoutGivingMedicalAdvice() {
        let draft = OfflineAgent.interpret("Necesito insulina en Chinatown")

        XCTAssertEqual(draft.resource, .medicine)
        XCTAssertTrue(draft.note.isEmpty)
        XCTAssertFalse(draft.summary.localizedCaseInsensitiveContains("dosis recomendada"))
    }

    func testDoesNotRetainPossibleExactAddress() {
        let draft = OfflineAgent.interpret("Necesito agua en 123 Mission Street urgente")

        XCTAssertTrue(draft.area.isEmpty)
        XCTAssertTrue(draft.missingFields.contains(.area))
        XCTAssertTrue(draft.notices.contains(where: { $0.contains("dirección exacta") }))
    }
}
