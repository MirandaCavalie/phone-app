import XCTest
@testable import BarrioMeshCore

final class MeshSecurityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func post(_ author: String, _ kind: PostKind = .need) -> MeshPost {
        MeshPost(
            authorID: author, authorName: author.capitalized, kind: kind, resource: .water, quantity: 2,
            unit: "botellas", urgency: .urgent, area: "Chacao", note: "", createdAt: now,
            expiresAt: now.addingTimeInterval(3_600)
        )
    }

    private func signed(_ state: MeshState, by author: String, _ identity: AgentIdentity) -> MeshState {
        var state = state
        state.signatures += MeshSecurity.sign(state, authorID: author, with: identity)
        return state
    }

    func testSignedItemsAreAcceptedAndUnsignedOnesDropped() {
        let ana = AgentIdentity()
        let good = post(ana.agentID)
        let forged = post(ana.agentID)
        var incoming = signed(MeshState(posts: [good]), by: ana.agentID, ana)
        incoming.posts.append(forged)

        let verdict = MeshSecurity.verify(incoming, known: MeshState())
        XCTAssertEqual(verdict.accepted.posts.map(\.id), [good.id])
        XCTAssertEqual(verdict.rejected, 1)
    }

    func testTamperedContentFailsVerification() {
        let ana = AgentIdentity()
        let original = post(ana.agentID)
        let state = signed(MeshState(posts: [original]), by: ana.agentID, ana)
        let tampered = MeshPost(
            id: original.id, authorID: ana.agentID, authorName: "Ana", kind: .need, resource: .water, quantity: 50,
            unit: "botellas", urgency: .urgent, area: "Chacao", note: "", createdAt: now, expiresAt: original.expiresAt
        )
        let verdict = MeshSecurity.verify(MeshState(posts: [tampered], signatures: state.signatures), known: MeshState())
        XCTAssertTrue(verdict.accepted.posts.isEmpty)
    }

    func testClosingAPostKeepsItsSignatureValid() {
        let ana = AgentIdentity()
        var original = post(ana.agentID)
        let state = signed(MeshState(posts: [original]), by: ana.agentID, ana)
        original.closedAt = now
        let verdict = MeshSecurity.verify(MeshState(posts: [original], signatures: state.signatures), known: MeshState())
        XCTAssertEqual(verdict.accepted.posts.count, 1)
    }

    func testNobodyCanSpeakForAnotherAgentEvenOnFirstContact() {
        let real = AgentIdentity()
        let impostor = AgentIdentity()

        // The impostor forges an "accept" from Luis with its own key, before Luis was ever seen.
        let fake = AgentMessage(proposalID: "x", senderID: real.agentID, senderName: "Luis", kind: .accept, rationale: "", sentAt: now)
        let attack = signed(MeshState(messages: [fake]), by: real.agentID, impostor)
        XCTAssertTrue(MeshSecurity.verify(attack, known: MeshState()).accepted.messages.isEmpty)

        // The real Luis is trusted, with no pinning needed.
        let genuine = signed(MeshState(messages: [fake]), by: real.agentID, real)
        XCTAssertEqual(MeshSecurity.verify(genuine, known: MeshState()).accepted.messages.count, 1)
    }

    func testAgentIDsAreDerivedFromKeys() {
        let identity = AgentIdentity()
        XCTAssertEqual(identity.agentID, MeshSecurity.agentID(for: identity.publicKey))
        XCTAssertNotEqual(identity.agentID, AgentIdentity().agentID)
        XCTAssertEqual(AgentIdentity.deterministic(seed: "luis").agentID, AgentIdentity.deterministic(seed: "luis").agentID)
    }

    func testApprovalsFromOutsidersAreStripped() {
        let need = post("ana")
        let offer = post("luis", .offer)
        let proposal = MatchProposal(needID: need.id, offerID: offer.id, approvals: ["ana", "mallory"], completions: ["mallory"])
        let verdict = MeshSecurity.verify(MeshState(proposals: [proposal]), known: MeshState(posts: [need, offer]))
        XCTAssertEqual(verdict.accepted.proposals.first?.approvals, ["ana"])
        XCTAssertEqual(verdict.accepted.proposals.first?.completions, [])
    }

    func testFamilyCheckInIsUnreadableWithoutTheCode() throws {
        let code = "ceiba-colibri-arepa-42"
        let circle = try XCTUnwrap(FamilyCircle.identifier(for: code))
        let plain = SafetyCheckIn(authorID: "rosa", authorName: "Rosa", circleID: circle, status: .needsHelp, area: "Petare", createdAt: now)
        let sealed = try XCTUnwrap(plain.sealed(withCircleCode: code))

        XCTAssertTrue(sealed.isSealed)
        XCTAssertEqual(sealed.authorName, "")
        XCTAssertEqual(sealed.area, "")
        let wire = String(decoding: try JSONEncoder().encode(sealed), as: UTF8.self)
        XCTAssertFalse(wire.contains("Rosa"))
        XCTAssertFalse(wire.contains("Petare"))

        XCTAssertNil(sealed.opened(withCircleCode: "otro-codigo"))
        let opened = try XCTUnwrap(sealed.opened(withCircleCode: "CEIBA colibri arepa 42"))
        XCTAssertEqual(opened.authorName, "Rosa")
        XCTAssertEqual(opened.status, .needsHelp)
        XCTAssertEqual(opened.area, "Petare")
    }

    func testAgentSealsItsCheckInsAndFamilyStillReadsThem() {
        let code = "guadua-tucan-mango-17"
        let rosa = PersonalAgent(selfID: "rosa", profile: AgentProfile(name: "Rosa", homeArea: "Petare", familyCircleCode: code), policy: AgentPolicy())
        let ana = PersonalAgent(selfID: "ana", profile: AgentProfile(name: "Ana", homeArea: "Chacao", familyCircleCode: code), policy: AgentPolicy())

        let sent = rosa.step(state: MeshState(), memory: rosa.activateEmergency(memory: AgentMemory(), reason: "t", now: now), connectivity: .offline, now: now)
        XCTAssertEqual(sent.checkIns.first?.isSealed, true)

        let received = ana.step(state: MeshState(checkIns: sent.checkIns), memory: AgentMemory(), connectivity: .offline, now: now)
        XCTAssertTrue(received.memory.log.contains { $0.kind == .family && $0.title.contains("Rosa") })
    }

    func testSuggestedCodesAreLongAndValid() {
        let code = FamilyCircle.suggestCode()
        XCTAssertGreaterThanOrEqual(code.split(separator: "-").count, 4)
        XCTAssertNotNil(FamilyCircle.identifier(for: code))
    }

    func testIdentityRoundTripsThroughRawRepresentation() throws {
        let identity = AgentIdentity()
        let restored = try AgentIdentity(rawRepresentation: identity.privateKey.rawRepresentation)
        XCTAssertEqual(restored.publicKey, identity.publicKey)
        XCTAssertEqual(identity.fingerprint.count, 11)
    }

    func testResendingKnownStateDoesNotCrashAndIsIdempotent() {
        // Regression: full-state gossip always resends known posts; verify used to trap on duplicate ids.
        let ana = AgentIdentity()
        let need = post(ana.agentID)
        let offer = post(ana.agentID, .offer)
        let state = signed(MeshState(posts: [need, offer], proposals: [MatchProposal(needID: need.id, offerID: offer.id)]), by: ana.agentID, ana)
        let store = MeshStore()
        store.merge(MeshSecurity.verify(state, known: store.state).accepted, now: now)

        let again = MeshSecurity.verify(store.state, known: store.state)
        XCTAssertEqual(again.rejected, 0)
        XCTAssertFalse(store.merge(again.accepted, now: now))
    }
}
