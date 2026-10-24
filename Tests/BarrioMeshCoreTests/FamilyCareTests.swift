import XCTest
@testable import BarrioMeshCore

final class FamilyCareTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }()

    /// Tuesday 10:30 in Bogotá.
    private var tuesdayMorning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10, minute: 30))!
    }

    private var diego: HouseholdMember {
        HouseholdMember(
            name: "Diego", relation: "hijo", phone: "+57 311 000 0000",
            routine: [RoutineBlock(place: "Colegio San José", area: "Usaquén", weekdays: [2, 3, 4, 5, 6], startMinute: 7 * 60 + 30, endMinute: 14 * 60, meetingPoint: "Patio central")]
        )
    }

    private var rosa: HouseholdMember {
        HouseholdMember(
            name: "Rosa", relation: "mamá",
            medical: MedicalCard(
                birthYear: 1950, bloodType: "O+", conditions: ["Diabetes tipo 1"], allergies: ["Penicilina"],
                medications: [Medication(name: "Insulina", dose: "10 U", times: [8 * 60, 20 * 60], needsRefrigeration: true, supplyDays: 2)]
            )
        )
    }

    func testRoutineTellsWhereSomeoneProbablyIs() {
        let atSchool = FamilyLocator.likelyLocation(of: diego, at: tuesdayMorning, homeArea: "Chapinero", calendar: calendar)
        XCTAssertEqual(atSchool.place, "Colegio San José")
        XCTAssertEqual(atSchool.meetingPoint, "Patio central")

        let evening = calendar.date(byAdding: .hour, value: 8, to: tuesdayMorning)!
        XCTAssertEqual(FamilyLocator.likelyLocation(of: diego, at: evening, homeArea: "Chapinero", calendar: calendar).place, "Casa")

        let saturday = calendar.date(byAdding: .day, value: 4, to: tuesdayMorning)!
        XCTAssertEqual(FamilyLocator.likelyLocation(of: diego, at: saturday, homeArea: "Chapinero", calendar: calendar).place, "Casa")
    }

    func testRefrigeratedMedicationImpliesPowerAndMedicineNeeds() {
        XCTAssertEqual(Set(rosa.effectiveNeeds), [.medicine, .power])
        XCTAssertTrue(rosa.isVulnerable)
        XCTAssertFalse(diego.isVulnerable)
    }

    func testMedicalSummaryIsDense() {
        let summary = rosa.medical.summary
        XCTAssertTrue(summary.contains("sangre O+"))
        XCTAssertTrue(summary.contains("Diabetes tipo 1"))
        XCTAssertTrue(summary.contains("Insulina"))
        XCTAssertTrue(summary.contains("Penicilina"))
    }

    func testNextDoseRollsOverToTomorrow() {
        let insulin = rosa.medical.medications[0]
        let next = insulin.nextDose(after: tuesdayMorning, calendar: calendar)!
        XCTAssertEqual(calendar.component(.hour, from: next), 20)
        let late = calendar.date(byAdding: .hour, value: 11, to: tuesdayMorning)!
        let tomorrow = insulin.nextDose(after: late, calendar: calendar)!
        XCTAssertEqual(calendar.component(.hour, from: tomorrow), 8)
        XCTAssertEqual(calendar.component(.day, from: tomorrow), 28)
    }

    func testLowMedicationShowsInPreparedness() {
        let profile = AgentProfile(name: "Ana", homeArea: "Chapinero", household: [rosa])
        XCTAssertTrue(profile.preparedness.gaps.contains { $0.contains("Insulina de Rosa: quedan 2 días") })
    }

    func testEmergencyLocatesFamilyAndPreparesAMessageForWhoeverIsAway() {
        var away = diego
        away.livesWithUser = false
        let agent = PersonalAgent(selfID: "me", profile: AgentProfile(name: "Ana", homeArea: "Chapinero", household: [rosa, away]), policy: AgentPolicy(), calendar: calendar)
        let memory = agent.activateEmergency(memory: AgentMemory(), reason: "test", now: tuesdayMorning)
        let result = agent.step(state: MeshState(), memory: memory, connectivity: .offline, now: tuesdayMorning)

        let familyLines = result.memory.log.filter { $0.kind == .family }.map(\.title)
        XCTAssertTrue(familyLines.contains { $0.hasPrefix("Rosa: probablemente en Casa") })
        XCTAssertTrue(familyLines.contains { $0.hasPrefix("Diego: probablemente en Colegio San José") })
        XCTAssertTrue(result.memory.outbox.contains { $0.recipientName == "Diego" && $0.body.contains("Patio central") })

        // Refrigerated insulin with no power at home becomes an urgent power request.
        XCTAssertTrue(result.posts.contains { $0.resource == .power && $0.urgency == .urgent })

        // Only once per emergency.
        let again = agent.step(state: MeshState(), memory: result.memory, connectivity: .offline, now: tuesdayMorning.addingTimeInterval(60))
        XCTAssertEqual(again.memory.log.filter { $0.kind == .family }.count, familyLines.count)
    }

    func testCallScriptAndReportCarryMedicalCardsAndWhereabouts() {
        var away = diego
        away.livesWithUser = false
        let profile = AgentProfile(name: "Ana", homeArea: "Chapinero", household: [rosa, away])
        let script = Paperwork.callScript(profile: profile, state: MeshState(), selfID: "me", now: tuesdayMorning, calendar: calendar)
        XCTAssertTrue(script.text.contains("Rosa: "))
        XCTAssertTrue(script.text.contains("Insulina"))
        XCTAssertTrue(script.text.contains("Somos 2 personas"), "Diego lives elsewhere")

        let report = Paperwork.report(profile: profile, memory: AgentMemory(), state: MeshState(), selfID: "me", now: tuesdayMorning, calendar: calendar).plainText
        XCTAssertTrue(report.contains("FICHAS MÉDICAS"))
        XCTAssertTrue(report.contains("DÓNDE ESTABA CADA FAMILIAR"))
    }

    func testOldProfilesWithoutMedicalCardsStillLoad() throws {
        let json = #"{"id":"6F1B2C4D-0000-4000-8000-000000000001","name":"Rosa","relation":"mamá","dependsOn":["medicine"]}"#
        let member = try JSONDecoder().decode(HouseholdMember.self, from: Data(json.utf8))
        XCTAssertTrue(member.livesWithUser)
        XCTAssertTrue(member.medical.isEmpty)
        XCTAssertEqual(member.dependsOn, [.medicine])
    }
}
