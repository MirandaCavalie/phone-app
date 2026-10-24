import Foundation
import XCTest
@testable import BarrioMeshCore

final class MeshStoreTests: XCTestCase {
    func testMergeIsIdempotentAndAddsUnknownPosts() {
        let store = MeshStore()
        let post = samplePost(author: "peer-a", kind: .need)
        let incoming = MeshState(posts: [post])

        XCTAssertTrue(store.merge(incoming, now: post.createdAt))
        XCTAssertFalse(store.merge(incoming, now: post.createdAt))
        XCTAssertEqual(store.state.posts, [post])
    }

    func testProposalMergePreservesConcurrentApprovals() {
        let need = samplePost(author: "peer-a", kind: .need)
        let offer = samplePost(author: "peer-b", kind: .offer)
        let fromA = MatchProposal(
            needID: need.id,
            offerID: offer.id,
            approvals: ["peer-a"]
        )
        let fromB = MatchProposal(
            needID: need.id,
            offerID: offer.id,
            approvals: ["peer-b"]
        )
        let store = MeshStore(initialState: MeshState(posts: [need, offer], proposals: [fromA]))

        XCTAssertTrue(store.merge(MeshState(proposals: [fromB])))
        let merged = store.state.proposals[0]
        XCTAssertEqual(merged.approvals, ["peer-a", "peer-b"])
        XCTAssertEqual(merged.status(requiredPeers: ["peer-a", "peer-b"]), .accepted)
    }

    func testPersistsAndReloadsState() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("mesh-state.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        let original = MeshStore(fileURL: file)
        let post = samplePost(author: "peer-a", kind: .offer)
        XCTAssertTrue(original.add(post))

        let reloaded = MeshStore(fileURL: file)
        XCTAssertEqual(reloaded.state.posts, [post])
    }

    private func samplePost(author: String, kind: PostKind) -> MeshPost {
        MeshPost(
            authorID: author,
            authorName: author,
            kind: kind,
            resource: .water,
            quantity: 2,
            unit: "botellas",
            urgency: .important,
            area: "Mission",
            note: "",
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 10_000)
        )
    }
}
