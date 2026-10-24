import XCTest
@testable import BarrioMeshCore

/// Failure modes found while reviewing the agent: over-commitment, stuck negotiations,
/// partial help never completed, unfair allocation, and unbounded state.
final class AgentRobustnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func post(_ author: String, _ kind: PostKind, quantity: Int, urgency: Urgency = .important, createdAt: Date? = nil) -> MeshPost {
        MeshPost(
            authorID: author, authorName: author.capitalized, kind: kind, resource: .water,
            quantity: quantity, unit: "botellas", urgency: urgency, area: "Chapinero", note: "",
            createdAt: createdAt ?? now, expiresAt: now.addingTimeInterval(6 * 3_600)
        )
    }

    private func ask(_ need: MeshPost, _ offer: MeshPost, quantity: Int, at date: Date? = nil) -> (MatchProposal, AgentMessage) {
        let proposal = MatchProposal(needID: need.id, offerID: offer.id, createdAt: now)
        let message = AgentMessage(
            proposalID: proposal.id, senderID: need.authorID, senderName: need.authorName, kind: .propose,
            terms: MeetingTerms(quantity: quantity, meetingPoint: "Parque", meetAt: now.addingTimeInterval(1_800)),
            rationale: "", sentAt: date ?? now
        )
        return (proposal, message)
    }

    private func applying(_ state: MeshState, _ result: AgentStepResult) -> MeshState {
        PersonalAgent.overlay(state, with: result)
    }

    private func giver(limit: Int = 10) -> PersonalAgent {
        PersonalAgent(selfID: "luis", profile: AgentProfile(name: "Luis", homeArea: "Chapinero"), policy: AgentPolicy(autoGiveLimit: limit))
    }

    private func receiver(_ id: String) -> PersonalAgent {
        PersonalAgent(selfID: id, profile: AgentProfile(name: id.capitalized, homeArea: "Chapinero", meetingPoint: "Parque"), policy: AgentPolicy())
    }

    func testGiverNeverCommitsMoreThanItHasWhenTwoRequestsArriveTogether() {
        let offer = post("luis", .offer, quantity: 3)
        let ana = post("ana", .need, quantity: 2)
        let beto = post("beto", .need, quantity: 2)
        let (p1, m1) = ask(ana, offer, quantity: 2)
        let (p2, m2) = ask(beto, offer, quantity: 2, at: now.addingTimeInterval(1))
        let state = MeshState(posts: [offer, ana, beto], proposals: [p1, p2], messages: [m1, m2])

        let result = giver().step(state: state, memory: AgentMemory(), connectivity: .offline, now: now)
        let committed = result.messages.compactMap { message -> Int? in
            guard message.kind == .accept || message.kind == .counter else { return nil }
            return message.terms?.quantity
        }.reduce(0, +)

        XCTAssertEqual(committed, 3, "2 + a counter of 1, never 4")
        XCTAssertEqual(result.messages.first(where: { $0.proposalID == p2.id })?.kind, .counter)
    }

    func testUrgentRequestIsServedFirstEvenIfItArrivedLater() {
        let offer = post("luis", .offer, quantity: 2)
        let early = post("ana", .need, quantity: 2, urgency: .normal)
        let abuela = post("rosa", .need, quantity: 2, urgency: .urgent)
        let (p1, m1) = ask(early, offer, quantity: 2)
        let (p2, m2) = ask(abuela, offer, quantity: 2, at: now.addingTimeInterval(60))
        let state = MeshState(posts: [offer, early, abuela], proposals: [p1, p2], messages: [m1, m2])

        let result = giver().step(state: state, memory: AgentMemory(), connectivity: .offline, now: now.addingTimeInterval(61))

        XCTAssertEqual(result.messages.first(where: { $0.proposalID == p2.id })?.kind, .accept)
        XCTAssertEqual(result.messages.first(where: { $0.proposalID == p1.id })?.kind, .decline)
        XCTAssertTrue(result.memory.log.contains(where: { $0.detail.contains("urgente") }))
    }

    func testUnansweredProposalIsWithdrawnAndTheAgentTriesAnotherNeighbor() {
        let need = post("ana", .need, quantity: 2)
        let silent = post("luis", .offer, quantity: 2)
        let other = post("marta", .offer, quantity: 2, createdAt: now.addingTimeInterval(5))
        let ana = receiver("ana")

        // First step: proposes to the best candidate only.
        var state = MeshState(posts: [need, silent, other])
        let first = ana.step(state: state, memory: AgentMemory(), connectivity: .offline, now: now)
        XCTAssertEqual(first.messages.filter { $0.kind == .propose }.count, 1)
        state = applying(state, first)
        let firstTarget = first.messages[0].proposalID

        // Nothing happens before the timeout.
        let waiting = ana.step(state: state, memory: first.memory, connectivity: .offline, now: now.addingTimeInterval(60))
        XCTAssertTrue(waiting.messages.isEmpty)

        // After the timeout it withdraws and proposes to the other neighbor.
        let later = now.addingTimeInterval(PersonalAgent.negotiationTimeout + 1)
        let retry = ana.step(state: state, memory: first.memory, connectivity: .offline, now: later)
        XCTAssertEqual(retry.messages.first(where: { $0.proposalID == firstTarget })?.kind, .decline)
        let newProposal = retry.messages.first(where: { $0.kind == .propose })
        XCTAssertNotNil(newProposal)
        XCTAssertNotEqual(newProposal?.proposalID, firstTarget)
    }

    func testPartialHelpKeepsLookingForTheRest() {
        let need = post("ana", .need, quantity: 4)
        let luis = post("luis", .offer, quantity: 2)
        let marta = post("marta", .offer, quantity: 5)
        let (p1, m1) = ask(need, luis, quantity: 2)
        let accept = AgentMessage(proposalID: p1.id, senderID: "luis", senderName: "Luis", kind: .accept, terms: m1.terms, respondsTo: m1.id, rationale: "", sentAt: now)
        let state = MeshState(posts: [need, luis, marta], proposals: [p1], messages: [m1, accept])

        let result = receiver("ana").step(state: state, memory: AgentMemory(), connectivity: .offline, now: now)
        let proposal = result.messages.first(where: { $0.kind == .propose })

        XCTAssertEqual(proposal?.terms?.quantity, 2, "asks Marta only for the 2 still missing")
        XCTAssertEqual(proposal?.proposalID, MatchProposal.makeID(needID: need.id, offerID: marta.id))
    }

    func testFullyCoveredNeedStopsProposing() {
        let need = post("ana", .need, quantity: 2)
        let luis = post("luis", .offer, quantity: 2)
        let marta = post("marta", .offer, quantity: 5)
        let (p1, m1) = ask(need, luis, quantity: 2)
        let accept = AgentMessage(proposalID: p1.id, senderID: "luis", senderName: "Luis", kind: .accept, terms: m1.terms, respondsTo: m1.id, rationale: "", sentAt: now)
        let state = MeshState(posts: [need, luis, marta], proposals: [p1], messages: [m1, accept])

        let result = receiver("ana").step(state: state, memory: AgentMemory(), connectivity: .offline, now: now)
        XCTAssertFalse(result.messages.contains(where: { $0.kind == .propose }))
    }

    func testCompactionForgetsDeadHistoryAndPeersCannotResurrectIt() {
        let old = MeshPost(
            authorID: "ana", authorName: "Ana", kind: .need, resource: .water, quantity: 1, unit: "botellas",
            urgency: .normal, area: "Chapinero", note: "",
            createdAt: now.addingTimeInterval(-86_400), expiresAt: now.addingTimeInterval(-80_000)
        )
        let live = post("luis", .offer, quantity: 2)
        let (proposal, message) = ask(old, live, quantity: 1)
        let oldCheckIn = SafetyCheckIn(authorID: "rosa", authorName: "Rosa", circleID: "c", status: .safe, area: "x", createdAt: now.addingTimeInterval(-3_600))
        let newCheckIn = SafetyCheckIn(authorID: "rosa", authorName: "Rosa", circleID: "c", status: .needsHelp, area: "x", createdAt: now)

        let store = MeshStore(initialState: MeshState(posts: [old, live], proposals: [proposal], messages: [message], checkIns: [oldCheckIn, newCheckIn]))
        XCTAssertTrue(store.compact(now: now))
        XCTAssertEqual(store.state.posts.map(\.id), [live.id])
        XCTAssertTrue(store.state.proposals.isEmpty)
        XCTAssertTrue(store.state.messages.isEmpty)
        XCTAssertEqual(store.state.checkIns.map(\.id), [newCheckIn.id])

        XCTAssertFalse(store.merge(MeshState(posts: [old]), now: now), "a peer that has not compacted cannot bring it back")
    }

    func testPendingHumanDecisionReservesUnits() {
        // Limit 1: a request for 2 needs a human; a second request in the same step must not reuse those units.
        let offer = post("luis", .offer, quantity: 2)
        let ana = post("ana", .need, quantity: 2, urgency: .urgent)
        let beto = post("beto", .need, quantity: 2)
        let (p1, m1) = ask(ana, offer, quantity: 2)
        let (p2, m2) = ask(beto, offer, quantity: 2, at: now.addingTimeInterval(1))
        let state = MeshState(posts: [offer, ana, beto], proposals: [p1, p2], messages: [m1, m2])

        let result = giver(limit: 1).step(state: state, memory: AgentMemory(), connectivity: .offline, now: now)
        XCTAssertEqual(result.memory.pending.count, 1)
        XCTAssertEqual(result.messages.first(where: { $0.proposalID == p2.id })?.kind, .decline)
    }
}
