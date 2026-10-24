import XCTest
@testable import BarrioMeshCore

/// Simulates two phones: each agent steps on its own copy of the mesh state, and the
/// copies are exchanged the way Bluetooth gossip would exchange them.
final class PersonalAgentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeAna(policy: AgentPolicy = AgentPolicy()) -> PersonalAgent {
        PersonalAgent(
            selfID: "ana",
            profile: AgentProfile(
                name: "Ana",
                country: .colombia,
                homeArea: "Chapinero",
                meetingPoint: "Parque de los Hippies",
                household: [HouseholdMember(name: "Rosa", relation: "mamá")],
                standingNeeds: [StandingNeed(resource: .water, quantity: 4, urgency: .urgent)],
                familyContacts: [FamilyContact(name: "Tío Juan", phone: "+57 300 123 4567")],
                familyCircleCode: "familia-ana"
            ),
            policy: policy
        )
    }

    private func makeLuis(policy: AgentPolicy = AgentPolicy()) -> PersonalAgent {
        PersonalAgent(
            selfID: "luis",
            profile: AgentProfile(
                name: "Luis",
                country: .colombia,
                homeArea: "Chapinero",
                supplies: [Supply(resource: .water, quantity: 10, reserve: 8)]
            ),
            policy: policy
        )
    }

    private func store(_ state: MeshState, applying result: AgentStepResult) -> MeshState {
        let store = MeshStore(initialState: state)
        store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns)
        return store.state
    }

    private func gossip(_ a: inout MeshState, _ b: inout MeshState) {
        let storeA = MeshStore(initialState: a)
        storeA.merge(b)
        let storeB = MeshStore(initialState: b)
        storeB.merge(storeA.state)
        a = storeA.state
        b = storeB.state
    }

    func testOutageActivatesEmergencyChecksInAndPublishesFromProfile() {
        let ana = makeAna()
        var memory = ana.step(state: MeshState(), memory: AgentMemory(), connectivity: .online, now: now).memory
        XCTAssertFalse(memory.emergencyActive)

        let result = ana.step(state: MeshState(), memory: memory, connectivity: .offline, now: now)
        memory = result.memory

        XCTAssertTrue(memory.emergencyActive)
        XCTAssertEqual(result.checkIns.count, 1)
        XCTAssertEqual(result.checkIns.first?.circleID, FamilyCircle.identifier(for: "familia-ana"))
        XCTAssertEqual(result.posts.map(\.resource), [.water])
        XCTAssertEqual(memory.unsentOutbox.count, 1)
        XCTAssertEqual(memory.unsentOutbox.first?.phone, "573001234567")

        // A second step does not repeat any of it.
        let again = ana.step(state: store(MeshState(), applying: result), memory: memory, connectivity: .offline, now: now)
        XCTAssertFalse(again.changesMesh)
    }

    func testTwoAgentsNegotiateAPartialHandoffWithoutHumans() {
        let ana = makeAna()
        let luis = makeLuis()
        var anaState = MeshState()
        var luisState = MeshState()
        var anaMemory = AgentMemory()
        var luisMemory = AgentMemory()
        anaMemory.lastConnectivity = .online
        luisMemory.lastConnectivity = .online

        // Both phones lose internet; each agent publishes from its own profile.
        var a = ana.step(state: anaState, memory: anaMemory, connectivity: .offline, now: now)
        anaState = store(anaState, applying: a); anaMemory = a.memory
        var l = luis.step(state: luisState, memory: luisMemory, connectivity: .offline, now: now)
        luisState = store(luisState, applying: l); luisMemory = l.memory
        XCTAssertEqual(l.posts.first?.quantity, 2, "Luis offers only what is above his reserve")

        // Phones meet. Ana's agent (the one who needs) proposes.
        gossip(&anaState, &luisState)
        a = ana.step(state: anaState, memory: anaMemory, connectivity: .offline, now: now)
        anaState = store(anaState, applying: a); anaMemory = a.memory
        XCTAssertEqual(a.messages.map(\.kind), [.propose])
        XCTAssertEqual(a.messages.first?.terms?.quantity, 2)

        // Luis's agent accepts within its autonomous limit.
        gossip(&anaState, &luisState)
        l = luis.step(state: luisState, memory: luisMemory, connectivity: .offline, now: now)
        luisState = store(luisState, applying: l); luisMemory = l.memory
        XCTAssertEqual(l.messages.map(\.kind), [.accept])

        gossip(&anaState, &luisState)
        a = ana.step(state: anaState, memory: anaMemory, connectivity: .offline, now: now)
        anaMemory = a.memory

        let proposalID = try! XCTUnwrap(anaState.proposals.first?.id)
        let terms = anaState.negotiation(for: proposalID).agreedTerms
        XCTAssertEqual(terms?.quantity, 2)
        XCTAssertEqual(terms?.meetingPoint, "Parque de los Hippies")
        XCTAssertTrue(anaMemory.log.contains(where: { $0.kind == .agreement }))
        XCTAssertTrue(luisMemory.log.contains(where: { $0.kind == .agreement }))

        // After the meeting time the agent follows up and closes the loop when approved.
        let later = now.addingTimeInterval(3_600)
        a = ana.step(state: anaState, memory: anaMemory, connectivity: .offline, now: later)
        anaMemory = a.memory
        let followUp = try! XCTUnwrap(anaMemory.pending.first(where: { $0.id.hasPrefix("followup:") }))
        let completion = ana.approve(followUp.id, state: anaState, memory: anaMemory, now: later)
        XCTAssertEqual(completion.proposals.first?.completions, ["ana"])
        XCTAssertTrue(completion.memory.pending.isEmpty)
    }

    func testGiverCountersWhenAskedForMoreThanItCanShare() {
        let luis = makeLuis()
        var state = MeshState()
        var memory = AgentMemory()
        memory.lastConnectivity = .online
        let published = luis.step(state: state, memory: memory, connectivity: .offline, now: now)
        state = store(state, applying: published)
        memory = published.memory
        let offerPost = try! XCTUnwrap(published.posts.first)

        // A neighbor without an agent-side counter asks for 5 directly.
        let need = MeshPost(
            authorID: "marta", authorName: "Marta", kind: .need, resource: .water, quantity: 5,
            unit: "botellas", urgency: .urgent, area: "Chapinero", note: "",
            createdAt: now, expiresAt: now.addingTimeInterval(3_600)
        )
        let proposalID = MatchProposal.makeID(needID: need.id, offerID: offerPost.id)
        let ask = AgentMessage(
            proposalID: proposalID, senderID: "marta", senderName: "Marta", kind: .propose,
            terms: MeetingTerms(quantity: 5, meetingPoint: "Iglesia", meetAt: now), rationale: "", sentAt: now
        )
        state = store(state, applying: {
            var r = AgentStepResult(memory: memory)
            r.posts = [need]
            r.proposals = [MatchProposal(needID: need.id, offerID: offerPost.id)]
            r.messages = [ask]
            return r
        }())

        let response = luis.step(state: state, memory: memory, connectivity: .offline, now: now)
        XCTAssertEqual(response.messages.first?.kind, .counter)
        XCTAssertEqual(response.messages.first?.terms?.quantity, 2)
    }

    func testMedicineAlwaysNeedsHumanApproval() {
        var profile = makeAna().profile
        profile.standingNeeds = [StandingNeed(resource: .medicine, quantity: 1, urgency: .urgent, reason: "Insulina de Rosa")]
        let agent = PersonalAgent(selfID: "ana", profile: profile, policy: AgentPolicy())
        var memory = AgentMemory()
        memory = agent.activateEmergency(memory: memory, reason: "test", now: now)

        let result = agent.step(state: MeshState(), memory: memory, connectivity: .offline, now: now)
        XCTAssertTrue(result.posts.isEmpty)
        XCTAssertEqual(result.memory.pending.filter { $0.id.hasPrefix("need:") }.count, 1)

        let pendingID = result.memory.pending.first(where: { $0.id.hasPrefix("need:") })!.id
        let approved = agent.approve(pendingID, state: MeshState(), memory: result.memory, now: now)
        XCTAssertEqual(approved.posts.first?.resource, .medicine)

        // Dismissed questions are not asked again.
        let dismissed = agent.dismiss(pendingID, memory: result.memory, now: now)
        let next = agent.step(state: MeshState(), memory: dismissed, connectivity: .offline, now: now)
        XCTAssertFalse(next.memory.pending.contains(where: { $0.id == pendingID }))
    }

    func testDependentNeedsBecomeUrgentRequestsWhenUncovered() {
        var profile = makeAna().profile
        profile.standingNeeds = []
        profile.household = [HouseholdMember(name: "Rosa", relation: "mamá", dependsOn: [.power])]
        let agent = PersonalAgent(selfID: "ana", profile: profile, policy: AgentPolicy())
        let memory = agent.activateEmergency(memory: AgentMemory(), reason: "test", now: now)

        let result = agent.step(state: MeshState(), memory: memory, connectivity: .offline, now: now)
        XCTAssertEqual(result.posts.first?.resource, .power)
        XCTAssertEqual(result.posts.first?.urgency, .urgent)
    }

    func testFamilyCheckInsAreRecognizedOnlyWithinTheCircle() {
        let ana = makeAna()
        let circle = try! XCTUnwrap(FamilyCircle.identifier(for: "FAMILIA ana"))
        let mom = SafetyCheckIn(authorID: "rosa", authorName: "Rosa", circleID: circle, status: .safe, area: "Usaquén", createdAt: now)
        let stranger = SafetyCheckIn(authorID: "x", authorName: "X", circleID: "other", status: .safe, area: "Bosa", createdAt: now)

        let result = ana.step(state: MeshState(checkIns: [mom, stranger]), memory: AgentMemory(), connectivity: .offline, now: now)
        let familyEntries = result.memory.log.filter { $0.kind == .family }
        XCTAssertEqual(familyEntries.count, 1)
        XCTAssertTrue(familyEntries[0].title.contains("Rosa"))
    }

    func testVersionOneStateStillDecodes() throws {
        let json = #"{"posts":[],"proposals":[]}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(MeshState.self, from: json)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.checkIns.isEmpty)
    }

    func testPreparednessFindsGaps() {
        let report = AgentProfile(name: "A", homeArea: "B").preparedness
        XCTAssertLessThan(report.score, 50)
        XCTAssertFalse(report.gaps.isEmpty)
    }
}

final class ProfileInterpreterTests: XCTestCase {
    func testLearnsHouseholdSuppliesAndDependents() {
        let result = ProfileInterpreter.interpret(
            "Vivo en Chapinero con mi mamá que usa insulina. Tengo 12 botellas de agua, tengo carro y soy enfermera."
        )
        let profile = result.profile

        XCTAssertEqual(profile.homeArea, "Chapinero")
        XCTAssertEqual(profile.household.first?.relation, "mamá")
        XCTAssertEqual(profile.household.first?.dependsOn, [.medicine])
        XCTAssertEqual(profile.supplies.first(where: { $0.resource == .water })?.quantity, 12)
        XCTAssertEqual(profile.supplies.first(where: { $0.resource == .water })?.shareable, 6)
        XCTAssertNotNil(profile.supplies.first(where: { $0.resource == .transport }))
        XCTAssertNotNil(profile.supplies.first(where: { $0.resource == .firstAid }))
        XCTAssertFalse(result.learned.isEmpty)
    }

    func testLearnsStandingNeeds() {
        let result = ProfileInterpreter.interpret("Vivo en Petare y no tenemos agua guardada")
        XCTAssertEqual(result.profile.homeArea, "Petare")
        XCTAssertEqual(result.profile.standingNeeds.first?.resource, .water)
    }
}
