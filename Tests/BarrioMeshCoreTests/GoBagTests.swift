import XCTest
@testable import BarrioMeshCore

final class GoBagTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private var profile: AgentProfile {
        AgentProfile(
            name: "Miranda", country: .peru, homeArea: "Miraflores",
            household: [HouseholdMember(name: "Rosa", relation: "mamá", medical: MedicalCard(medications: [Medication(name: "Insulina", times: [480], needsRefrigeration: true)]))]
        )
    }

    func testRecommendationScalesWithHouseholdAndIncludesMedication() {
        let list = GoBag.recommended(for: profile)
        XCTAssertEqual(list.first { $0.kind == .water }?.quantity, 18, "2 people × 3 L × 3 days")
        XCTAssertEqual(list.first { $0.kind == .whistle }?.quantity, 2)
        let insulin = list.first { $0.kind == .medication }
        XCTAssertEqual(insulin?.label, "Insulina (Rosa)")
        XCTAssertTrue(insulin?.reason.contains("bolsa fría") == true)
    }

    func testAuditFindsMissingShortAndExpiring() {
        let bag = [
            GoBagItem(kind: .water, quantity: 10, expiresAt: now.addingTimeInterval(200 * 86_400)),
            GoBagItem(kind: .batteries, quantity: 8, expiresAt: now.addingTimeInterval(10 * 86_400)),
            GoBagItem(kind: .flashlight, quantity: 1),
            GoBagItem(kind: .food, quantity: 12, expiresAt: now.addingTimeInterval(-86_400))
        ]
        let gaps = GoBag.audit(bag, for: profile, now: now)
        XCTAssertEqual(gaps.first { $0.requirement.kind == .water }?.problem, .short(have: 10))
        XCTAssertEqual(gaps.first { $0.requirement.kind == .water }?.toBuy, 8)
        if case .expiring = gaps.first(where: { $0.requirement.kind == .batteries })?.problem {} else { XCTFail("batteries expiring") }
        XCTAssertEqual(gaps.first { $0.requirement.kind == .food }?.problem, .expired)
        XCTAssertNil(gaps.first { $0.requirement.kind == .flashlight })
        XCTAssertEqual(gaps.first { $0.requirement.kind == .radio }?.problem, .missing)
        XCTAssertLessThan(GoBag.readiness(bag, for: profile, now: now), 50)
    }

    func testOrderSkipsCashAndDocumentsAndBuildsAStoreMessage() {
        let order = SupplyOrder(gaps: GoBag.audit([], for: profile, now: now))
        XCTAssertFalse(order.lines.contains { $0.name.contains("Efectivo") || $0.name.contains("documentos") })
        XCTAssertTrue(order.lines.contains { $0.isMedication && $0.name == "Insulina (Rosa)" })
        let message = order.whatsAppMessage(customer: "Miranda", area: "Miraflores")
        XCTAssertTrue(message.contains("Miranda de Miraflores"))
        XCTAssertTrue(message.contains("Linterna ×1"))
    }

    func testMarketplaceLinksPerCountry() throws {
        let line = try XCTUnwrap(SupplyOrder(gaps: GoBag.audit([], for: profile, now: now)).lines.first { $0.name == "Linterna" })
        XCTAssertEqual(SupplyOrder.marketplaceURL(for: line, country: .peru)?.absoluteString, "https://listado.mercadolibre.com.pe/linterna-led")
        XCTAssertEqual(SupplyOrder.marketplaceURL(for: line, country: .colombia)?.host, "listado.mercadolibre.com.co")
    }

    func testProactiveAgentOffersToOrderWhatIsMissing() throws {
        var withStore = profile
        withStore.trustedStore = FamilyContact(name: "Bodega Don Pepe", phone: "51999111222")
        let suggestions = ProactiveAgent.suggestions(profile: withStore, memory: AgentMemory(), alerts: [], calendar: [], remindersScheduled: true, now: now)
        let bag = try XCTUnwrap(suggestions.first { $0.id.hasPrefix("gobag:") })
        XCTAssertEqual(bag.actionLabel, "Pedir a Bodega Don Pepe")
        guard case let .orderSupplies(order) = bag.action else { return XCTFail() }
        XCTAssertFalse(order.lines.isEmpty)

        let briefing = ProactiveAgent.briefing(profile: withStore, alerts: [], calendar: [], now: now)
        XCTAssertTrue(briefing.lines.contains { $0.hasPrefix("Mochila 0% lista") })
    }

    func testOlderProfilesWithoutGoBagStillLoad() throws {
        let profile = try JSONDecoder().decode(AgentProfile.self, from: Data(#"{"name":"Ana","country":"peru","homeArea":"Barranco"}"#.utf8))
        XCTAssertEqual(profile.name, "Ana")
        XCTAssertTrue(profile.goBag.isEmpty)
        XCTAssertNil(profile.trustedStore)
    }
}
