import XCTest
@testable import BarrioMeshCore

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Lang.current = .spanish
        super.tearDown()
    }

    func testEnglishHouseholdDescriptionIsUnderstood() {
        Lang.current = .english
        let result = ProfileInterpreter.interpret("I live in Miraflores with my mom who uses insulin. We need 4 bottles of water and I have a car.")
        XCTAssertEqual(result.profile.homeArea, "Miraflores")
        XCTAssertEqual(result.profile.household.first?.relation, "mom")
        XCTAssertEqual(result.profile.household.first?.dependsOn, [.medicine])
        XCTAssertEqual(result.profile.standingNeeds.first?.resource, .water)
        XCTAssertEqual(result.profile.standingNeeds.first?.quantity, 4)
        XCTAssertNotNil(result.profile.supplies.first(where: { $0.resource == .transport }))
        XCTAssertTrue(result.learned.contains { $0.hasPrefix("You live with your mom") })
    }

    func testAgentWritesItsLogInTheCurrentLanguage() {
        let agent = PersonalAgent(
            selfID: "me",
            profile: AgentProfile(name: "Ana", homeArea: "Miraflores", standingNeeds: [StandingNeed(resource: .water, quantity: 1)]),
            policy: AgentPolicy()
        )
        Lang.current = .english
        let english = agent.step(state: MeshState(), memory: agent.activateEmergency(memory: AgentMemory(), reason: "test", now: Date()), connectivity: .offline, now: Date())
        XCTAssertTrue(english.memory.log.contains { $0.title == "Requested 1 bottle of water" })

        Lang.current = .spanish
        let spanish = agent.step(state: MeshState(), memory: agent.activateEmergency(memory: AgentMemory(), reason: "test", now: Date()), connectivity: .offline, now: Date())
        XCTAssertTrue(spanish.memory.log.contains { $0.title == "Pedí 1 botella de agua" })
    }

    func testUnitsAndStatusesTranslate() {
        Lang.current = .english
        XCTAssertEqual(ResourceKind.water.amount(3), "3 bottles of water")
        XCTAssertEqual(ResourceKind.transport.count(1), "1 seat")
        XCTAssertEqual(SafetyStatus.safe.displayName, "I'm OK")
        Lang.current = .spanish
        XCTAssertEqual(ResourceKind.water.amount(1), "1 botella de agua")
    }
}
