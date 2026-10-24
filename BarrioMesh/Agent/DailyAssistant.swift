import EventKit
import Foundation
import UserNotifications

/// The phone-side hands of the proactive agent: reads today's calendar, adds events the
/// person approved, and schedules medication and morning reminders that work offline.
@MainActor
final class DailyAssistant: ObservableObject {
    @Published private(set) var todayEvents: [CalendarItem] = []
    @Published private(set) var calendarAccess = false
    @Published private(set) var remindersScheduled = UserDefaults.standard.bool(forKey: "faro.doseReminders")

    private let store = EKEventStore()

    func refreshCalendar() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        calendarAccess = granted
        guard granted else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        todayEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "", location: $0.location ?? "", start: $0.startDate, end: $0.endDate) }
    }

    /// Adds an event the person approved. Returns false if calendar access was refused.
    func addEvent(title: String, start: Date, durationMinutes: Int, notes: String) async -> Bool {
        if !calendarAccess { await refreshCalendar() }
        guard calendarAccess else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        do {
            try store.save(event, span: .thisEvent)
            await refreshCalendar()
            return true
        } catch {
            return false
        }
    }

    /// One repeating local notification per dose, plus a morning briefing at 7:30.
    func scheduleReminders(for profile: AgentProfile) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("faro.dose.") || $0 == "faro.briefing" }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        for member in profile.household {
            for medication in member.medical.medications {
                for minute in medication.times {
                    let content = UNMutableNotificationContent()
                    content.title = t("\(medication.name) para \(member.name)", "\(medication.name) for \(member.name)")
                    content.body = [medication.dose, medication.needsRefrigeration ? t("Mantener refrigerada.", "Keep it cold.") : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minute / 60, minute: minute % 60), repeats: true)
                    try? await center.add(UNNotificationRequest(identifier: "faro.dose.\(medication.id.uuidString).\(minute)", content: content, trigger: trigger))
                }
            }
        }

        let briefing = UNMutableNotificationContent()
        briefing.title = t("Tu día con Faro", "Your day with Faro")
        briefing.body = t("Agenda, familia, medicamentos y alertas de tu zona.", "Agenda, family, medications and alerts near you.")
        let morning = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 7, minute: 30), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "faro.briefing", content: briefing, trigger: morning))

        remindersScheduled = true
        UserDefaults.standard.set(true, forKey: "faro.doseReminders")
    }
}
