import Foundation
import XCTest
@testable import BarrioMeshCore

final class MatchEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMatchesCompatibleNeedAndOffer() {
        let need = post(author: "ana", kind: .need, resource: .water, quantity: 2, area: "Mission")
        let offer = post(author: "bruno", kind: .offer, resource: .water, quantity: 3, area: "mission")

        let matches = MatchEngine.candidates(in: [need, offer], at: now)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].need.id, need.id)
        XCTAssertEqual(matches[0].offer.id, offer.id)
        XCTAssertTrue(matches[0].reason.contains("misma zona"))
    }

    func testExcludesExpiredAndSelfMatches() {
        let expiredNeed = post(
            author: "ana",
            kind: .need,
            resource: .power,
            expiresAt: now.addingTimeInterval(-1)
        )
        let ownOffer = post(author: "ana", kind: .offer, resource: .power)
        let otherOffer = post(author: "bruno", kind: .offer, resource: .power)

        XCTAssertTrue(MatchEngine.candidates(in: [expiredNeed, ownOffer, otherOffer], at: now).isEmpty)
    }

    func testRanksUrgentLocalMatchFirst() {
        let urgentNeed = post(author: "ana", kind: .need, resource: .transport, urgency: .urgent, area: "SOMA")
        let normalNeed = post(author: "camila", kind: .need, resource: .transport, urgency: .normal, area: "Sunset")
        let offer = post(author: "bruno", kind: .offer, resource: .transport, quantity: 4, area: "SOMA")

        let matches = MatchEngine.candidates(in: [normalNeed, offer, urgentNeed], at: now)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].need.id, urgentNeed.id)
    }

    private func post(
        author: String,
        kind: PostKind,
        resource: ResourceKind,
        quantity: Int = 1,
        urgency: Urgency = .normal,
        area: String = "Mission",
        expiresAt: Date? = nil
    ) -> MeshPost {
        MeshPost(
            authorID: author,
            authorName: author.capitalized,
            kind: kind,
            resource: resource,
            quantity: quantity,
            unit: resource.defaultUnit,
            urgency: urgency,
            area: area,
            note: "",
            createdAt: now.addingTimeInterval(-60),
            expiresAt: expiresAt ?? now.addingTimeInterval(3_600)
        )
    }
}
