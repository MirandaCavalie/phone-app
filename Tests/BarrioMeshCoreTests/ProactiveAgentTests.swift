import XCTest
@testable import BarrioMeshCore

final class ProactiveAgentTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Lima")!
        return calendar
    }()

    /// Tuesday 07:15 in Lima.
    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 7, minute: 15))! }

    private var profile: AgentProfile {
        let insulin = Medication(name: "Insulina", dose: "10 U", times: [8 * 60, 20 * 60], needsRefrigeration: true, supplyDays: 2)
        return AgentProfile(
            name: "Miranda Cavalie", country: .peru, homeArea: "Miraflores", meetingPoint: "Parque Kennedy",
            household: [
                HouseholdMember(name: "Rosa", relation: "mamá", medical: MedicalCard(medications: [insulin], doctor: "Dra. Gómez", doctorPhone: "5114440000")),
                HouseholdMember(name: "Diego", relation: "hijo", livesWithUser: false, phone: "51999000000",
                                routine: [RoutineBlock(place: "Colegio Markham", area: "Miraflores", weekdays: [2, 3, 4, 5, 6], startMinute: 7 * 60 + 30, endMinute: 14 * 60, meetingPoint: "Cancha")])
            ]
        )
    }

    func testMorningBriefingCoversAgendaFamilyDosesAndGaps() {
        let meeting = CalendarItem(id: "1", title: "Reunión", location: "San Isidro", start: morning.addingTimeInterval(2 * 3_600), end: morning.addingTimeInterval(3 * 3_600))
        let briefing = ProactiveAgent.briefing(profile: profile, alerts: [], calendar: [meeting], now: morning, calendar: calendar)
        XCTAssertEqual(briefing.greeting, "Buenos días, Miranda.")
        XCTAssertTrue(briefing.lines.contains { $0.contains("Sin alertas cerca de Lima") })
        XCTAssertTrue(briefing.lines.contains { $0.contains("Reunión en San Isidro a las 9:15") })
        XCTAssertTrue(briefing.lines.contains { $0.contains("Diego: Colegio Markham 7:30–14:00") })
        XCTAssertTrue(briefing.lines.contains { $0.contains("Insulina de Rosa a las 8:00") })
    }

    func testSuggestsRefillCallDrillAndReminders() {
        let suggestions = ProactiveAgent.suggestions(profile: profile, memory: AgentMemory(), alerts: [], calendar: [], remindersScheduled: false, now: morning, calendar: calendar)
        let ids = suggestions.map(\.id)
        XCTAssertTrue(ids.contains { $0.hasPrefix("refill:") })
        XCTAssertTrue(ids.contains { $0.hasPrefix("refill-call:") })
        XCTAssertTrue(ids.contains("dose-reminders"))
        XCTAssertTrue(ids.contains { $0.hasPrefix("drill:") })

        guard case let .addToCalendar(_, start, _, notes) = suggestions.first(where: { $0.id.hasPrefix("refill:") })!.action else { return XCTFail() }
        XCTAssertEqual(calendar.component(.day, from: start), 28)
        XCTAssertEqual(calendar.component(.hour, from: start), 10)
        XCTAssertTrue(notes.contains("refrigeración"))

        guard case let .addToCalendar(_, drill, _, _) = suggestions.first(where: { $0.id.hasPrefix("drill:") })!.action else { return XCTFail() }
        XCTAssertEqual(calendar.component(.weekday, from: drill), 7, "Saturday")
    }

    func testAfterAWarningItOffersToMessageWhoeverIsAway() {
        let quake = HazardAlert(eventID: "emsc-9", source: "EMSC", kind: .earthquake, magnitude: 6.0, place: "Lima", epicenter: .init(latitude: -12.2, longitude: -76.9), depthKm: 30, occurredAt: morning, pagerLevel: nil, tsunamiFlag: false, url: "", relayedBy: "x")
        let assessment = HazardAssessment.assess(quake, home: profile.approximateLocation.point)
        XCTAssertGreaterThanOrEqual(assessment.level, .warning)
        let school = calendar.date(byAdding: .hour, value: 2, to: morning)!
        let suggestions = ProactiveAgent.suggestions(profile: profile, memory: AgentMemory(), alerts: [(quake, assessment)], calendar: [], remindersScheduled: true, now: school, calendar: calendar)
        let message = suggestions.first { $0.id.hasPrefix("alert-checkin:") }
        XCTAssertNotNil(message)
        guard case let .message(item) = message!.action else { return XCTFail() }
        XCTAssertEqual(item.recipientName, "Diego")
        XCTAssertTrue(item.body.contains("Cancha"))
    }

    func testDismissedSuggestionsStayHidden() {
        var memory = AgentMemory()
        memory.dismissedKeys.insert("dose-reminders")
        let suggestions = ProactiveAgent.suggestions(profile: profile, memory: memory, alerts: [], calendar: [], remindersScheduled: false, now: morning, calendar: calendar)
        XCTAssertFalse(suggestions.contains { $0.id == "dose-reminders" })
    }

    func testUpcomingDosesAreOrdered() {
        let doses = ProactiveAgent.upcomingDoses(profile: profile, now: morning, calendar: calendar)
        XCTAssertEqual(doses.count, 1, "only the next dose per medication")
        XCTAssertEqual(calendar.component(.hour, from: doses[0].at), 8)
    }
}
