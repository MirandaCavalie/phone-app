import Foundation
import BarrioMeshCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): "Check failed: \(message)"
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

let now = Date(timeIntervalSince1970: 2_000_000_000)

func makePost(
    author: String,
    kind: PostKind,
    resource: ResourceKind = .water,
    quantity: Int = 2,
    urgency: Urgency = .important,
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

do {
    let need = makePost(author: "ana", kind: .need, urgency: .urgent)
    let offer = makePost(author: "bruno", kind: .offer, quantity: 3, area: "mission")
    let matches = MatchEngine.candidates(in: [need, offer], at: now)
    try require(matches.count == 1, "compatible posts should match")
    try require(matches[0].reason.contains("misma zona"), "matching should normalize areas")

    let store = MeshStore(initialState: MeshState(posts: [need, offer]))
    let fromA = MatchProposal(needID: need.id, offerID: offer.id, approvals: ["ana"])
    let fromB = MatchProposal(needID: need.id, offerID: offer.id, approvals: ["bruno"])
    try require(store.upsert(fromA), "first proposal should be inserted")
    try require(store.merge(MeshState(proposals: [fromB])), "remote approval should merge")
    let merged = store.state.proposals[0]
    try require(merged.approvals == ["ana", "bruno"], "concurrent approvals should be preserved")
    try require(
        merged.status(requiredPeers: ["ana", "bruno"]) == .accepted,
        "two approvals should accept the proposal"
    )

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = folder.appendingPathComponent("state.json")
    defer { try? FileManager.default.removeItem(at: folder) }
    let persistent = MeshStore(fileURL: file)
    try require(persistent.add(need), "post should be persisted")
    try require(MeshStore(fileURL: file).state.posts == [need], "state should reload from disk")

    print("Core checks passed: matching, convergence, and persistence")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
