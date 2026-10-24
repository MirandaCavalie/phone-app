import XCTest
@testable import BarrioMeshCore

final class TrustedPeopleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let anaID = AgentIdentity.deterministic(seed: "ana")
    private let juanID = AgentIdentity.deterministic(seed: "juan")
    private let eveID = AgentIdentity.deterministic(seed: "eve")

    private func agent(_ identity: AgentIdentity, _ name: String, household: [HouseholdMember] = []) -> PersonalAgent {
        PersonalAgent(
            selfID: identity.agentID,
            profile: AgentProfile(name: name, homeArea: "Miraflores", household: household),
            policy: AgentPolicy(),
            agreementSecret: identity.agreementPrivateKey.rawRepresentation
        )
    }

    private func applying(_ state: MeshState, _ result: AgentStepResult) -> MeshState {
        PersonalAgent.overlay(state, with: result)
    }

    func testPairingSharingAndRevocation() throws {
        let diego = HouseholdMember(name: "Diego", relation: "hijo", livesWithUser: false,
                                    medical: MedicalCard(bloodType: "A+", allergies: ["Penicilina"]),
                                    routine: [RoutineBlock(place: "Colegio", weekdays: Set(1...7), startMinute: 0, endMinute: 1_439)])
        let ana = agent(anaID, "Ana", household: [diego])
        let juan = agent(juanID, "Juan")
        var state = MeshState()

        // Ana invites Juan, sharing safety, whereabouts and medical.
        let invite = ana.invite(agentID: juanID.agentID, name: "Juan", sharing: [.safety, .whereabouts, .medical], memory: AgentMemory(), now: now)
        var anaMemory = invite.memory
        state = applying(state, invite)
        XCTAssertEqual(anaMemory.trusted.first?.status, .invited)

        // Juan's agent asks Juan, who approves.
        var juanStep = juan.step(state: state, memory: AgentMemory(), connectivity: .online, now: now)
        let question = try XCTUnwrap(juanStep.memory.pending.first { $0.id.hasPrefix("trust:") })
        XCTAssertTrue(question.title.contains("Ana"))
        juanStep = juan.approve(question.id, state: state, memory: juanStep.memory, now: now)
        var juanMemory = juanStep.memory
        state = applying(state, juanStep)
        XCTAssertEqual(juanMemory.activeTrusted.map(\.agentID), [anaID.agentID])

        // Ana's agent sees the acceptance; both show the same pairing code.
        let anaStep = ana.step(state: state, memory: anaMemory, connectivity: .online, now: now)
        anaMemory = anaStep.memory
        XCTAssertEqual(anaMemory.activeTrusted.first?.agentID, juanID.agentID)
        XCTAssertEqual(anaMemory.trusted.first?.pairingCode, juanMemory.trusted.first?.pairingCode)
        XCTAssertEqual(anaMemory.trusted.first?.pairingCode.count, 6)

        // Emergency: Ana's agent shares with Juan, sealed for him.
        let emergency = ana.step(state: state, memory: ana.activateEmergency(memory: anaMemory, reason: "t", now: now), connectivity: .offline, now: now)
        anaMemory = emergency.memory
        state = applying(state, emergency)
        let share = try XCTUnwrap(state.trustMessages.first { $0.kind == .share })
        XCTAssertNotNil(share.sealed)
        let wire = String(decoding: try JSONEncoder().encode(share), as: UTF8.self)
        XCTAssertFalse(wire.contains("Diego"))
        XCTAssertFalse(wire.contains("Penicilina"))

        juanStep = juan.step(state: state, memory: juanMemory, connectivity: .offline, now: now)
        juanMemory = juanStep.memory
        let update = try XCTUnwrap(juanMemory.trustedUpdates[anaID.agentID])
        XCTAssertEqual(update.status, .safe)
        XCTAssertEqual(update.household.first?.location, "Colegio")
        XCTAssertTrue(update.household.first?.medical?.contains("Penicilina") == true)

        // A third agent relaying the same state cannot read it.
        XCTAssertNil(TrustNetwork.open(share, me: eveID.agentID, with: eveID.agreementPrivateKey))

        // Not re-shared within 30 minutes.
        let soon = ana.step(state: state, memory: anaMemory, connectivity: .offline, now: now.addingTimeInterval(600))
        XCTAssertTrue(soon.trustMessages.isEmpty)

        // Juan revokes; Ana's agent stops treating him as trusted.
        let revoke = juan.revoke(agentID: anaID.agentID, memory: juanMemory, now: now)
        state = applying(state, revoke)
        let afterRevoke = ana.step(state: state, memory: anaMemory, connectivity: .offline, now: now.addingTimeInterval(700))
        XCTAssertEqual(afterRevoke.memory.trusted.first?.status, .revoked)
    }

    func testScopesLimitWhatIsShared() throws {
        let rosa = HouseholdMember(name: "Rosa", relation: "mamá", medical: MedicalCard(conditions: ["Diabetes"]))
        let ana = agent(anaID, "Ana", household: [rosa])
        let person = TrustedPerson(agentID: juanID.agentID, name: "Juan", agreementKey: juanID.agreementPublicKey, status: .active,
                                   sharing: [.safety], theyShare: [], since: now, pairingCode: "000000", lastSharedAt: nil)
        var memory = ana.activateEmergency(memory: AgentMemory(), reason: "t", now: now)
        memory.trusted = [person]
        let result = ana.step(state: MeshState(), memory: memory, connectivity: .offline, now: now)
        let share = try XCTUnwrap(result.trustMessages.first { $0.kind == .share })
        let update = try XCTUnwrap(TrustNetwork.open(share, me: juanID.agentID, with: juanID.agreementPrivateKey))
        XCTAssertEqual(update.status, .safe)
        XCTAssertTrue(update.household.isEmpty, "whereabouts and medical were not granted")
    }

    func testForgedShareFromAnImpostorIsIgnored() {
        let juan = agent(juanID, "Juan")
        var memory = AgentMemory()
        memory.trusted = [TrustedPerson(agentID: anaID.agentID, name: "Ana", agreementKey: anaID.agreementPublicKey, status: .active,
                                        sharing: [.safety], theyShare: [.safety], since: now, pairingCode: "000000", lastSharedAt: nil)]
        // Eve claims to be Ana but can only seal with her own key.
        let fake = TrustedUpdate(fromName: "Ana", status: .needsHelp, area: "?", household: [], needs: ["dinero"], sentAt: now)
        let eveAsAna = TrustedPerson(agentID: juanID.agentID, name: "Juan", agreementKey: juanID.agreementPublicKey, status: .active,
                                     sharing: [], theyShare: [], since: now, pairingCode: "", lastSharedAt: nil)
        let sealed = TrustNetwork.seal(fake, from: anaID.agentID, to: eveAsAna, with: eveID.agreementPrivateKey)
        let message = TrustMessage(kind: .share, from: anaID.agentID, fromName: "Ana", to: juanID.agentID,
                                   agreementKey: eveID.agreementPublicKey, sealed: sealed, sentAt: now)
        let result = juan.step(state: MeshState(trustMessages: [message]), memory: memory, connectivity: .offline, now: now)
        XCTAssertNil(result.memory.trustedUpdates[anaID.agentID])
    }

    func testTrustedNeighborsAreServedFirst() {
        let luisID = AgentIdentity.deterministic(seed: "luis")
        var luisMemory = AgentMemory()
        luisMemory.trusted = [TrustedPerson(agentID: "ana", name: "Ana", agreementKey: Data(), status: .active,
                                            sharing: [.priorityHelp], theyShare: [], since: now, pairingCode: "", lastSharedAt: nil)]
        let luis = PersonalAgent(selfID: luisID.agentID, profile: AgentProfile(name: "Luis", homeArea: "Miraflores"), policy: AgentPolicy(autoGiveLimit: 10))
        let offer = MeshPost(authorID: luisID.agentID, authorName: "Luis", kind: .offer, resource: .water, quantity: 2, unit: "", urgency: .normal, area: "Miraflores", note: "", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
        let stranger = MeshPost(authorID: "beto", authorName: "Beto", kind: .need, resource: .water, quantity: 2, unit: "", urgency: .urgent, area: "Miraflores", note: "", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
        let friend = MeshPost(authorID: "ana", authorName: "Ana", kind: .need, resource: .water, quantity: 2, unit: "", urgency: .important, area: "Miraflores", note: "", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
        func ask(_ need: MeshPost, _ at: TimeInterval) -> (MatchProposal, AgentMessage) {
            let p = MatchProposal(needID: need.id, offerID: offer.id)
            return (p, AgentMessage(proposalID: p.id, senderID: need.authorID, senderName: need.authorName, kind: .propose,
                                    terms: MeetingTerms(quantity: 2, meetingPoint: "Parque", meetAt: now), rationale: "", sentAt: now.addingTimeInterval(at)))
        }
        let (p1, m1) = ask(stranger, 0)
        let (p2, m2) = ask(friend, 30)
        let result = luis.step(state: MeshState(posts: [offer, stranger, friend], proposals: [p1, p2], messages: [m1, m2]), memory: luisMemory, connectivity: .offline, now: now.addingTimeInterval(60))
        XCTAssertEqual(result.messages.first { $0.proposalID == p2.id }?.kind, .accept, "trusted friend first, even over a stranger's urgent request")
        XCTAssertEqual(result.messages.first { $0.proposalID == p1.id }?.kind, .decline)
    }

    func testAgreementKeyIsStableAndDistinct() {
        XCTAssertEqual(anaID.agreementPublicKey, AgentIdentity.deterministic(seed: "ana").agreementPublicKey)
        XCTAssertNotEqual(anaID.agreementPublicKey, juanID.agreementPublicKey)
        XCTAssertEqual(TrustNetwork.pairingCode(anaID.agreementPublicKey, juanID.agreementPublicKey),
                       TrustNetwork.pairingCode(juanID.agreementPublicKey, anaID.agreementPublicKey))
    }
}

final class TrustedNotesTests: XCTestCase {
    func testNotesTravelSealedAndOnlyBetweenTrustedPeople() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let ana = AgentIdentity.deterministic(seed: "ana"), juan = AgentIdentity.deterministic(seed: "juan"), eve = AgentIdentity.deterministic(seed: "eve")
        func agent(_ id: AgentIdentity, _ name: String) -> PersonalAgent {
            PersonalAgent(selfID: id.agentID, profile: AgentProfile(name: name, homeArea: "Lima"), policy: AgentPolicy(), agreementSecret: id.agreementPrivateKey.rawRepresentation)
        }
        func trusted(_ other: AgentIdentity, _ name: String) -> AgentMemory {
            var memory = AgentMemory()
            memory.trusted = [TrustedPerson(agentID: other.agentID, name: name, agreementKey: other.agreementPublicKey, status: .active, sharing: [.safety], theyShare: [.safety], since: now, pairingCode: "", lastSharedAt: nil)]
            return memory
        }

        let sent = agent(ana, "Ana").sendNote(to: juan.agentID, text: "Estoy en el parque con Diego", memory: trusted(juan, "Juan"), now: now)
        let note = try XCTUnwrap(sent.trustMessages.first)
        XCTAssertEqual(note.kind, .note)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(note), as: UTF8.self).contains("parque"))
        XCTAssertEqual(sent.memory.trustedNotes.last?.fromMe, true)

        let received = agent(juan, "Juan").step(state: MeshState(trustMessages: [note]), memory: trusted(ana, "Ana"), connectivity: .offline, now: now)
        XCTAssertEqual(received.memory.trustedNotes.last?.text, "Estoy en el parque con Diego")
        XCTAssertTrue(received.memory.log.contains { $0.title == "Ana: Estoy en el parque con Diego" })

        XCTAssertNil(TrustNetwork.openNote(note, me: eve.agentID, with: eve.agreementPrivateKey))
        XCTAssertTrue(agent(ana, "Ana").sendNote(to: eve.agentID, text: "hola", memory: trusted(juan, "Juan"), now: now).trustMessages.isEmpty, "not trusted")
    }
}
