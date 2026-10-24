import Foundation

/// An event from the person's own calendar, read on the phone (never shared).
public struct CalendarItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let location: String
    public let start: Date
    public let end: Date

    public init(id: String, title: String, location: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.location = location
        self.start = start
        self.end = end
    }
}

/// Something the agent offers to do for the person in calm times. The person taps once;
/// the app performs the action (calendar event, reminder, call, message).
public struct Suggestion: Equatable, Identifiable, Sendable {
    public enum Action: Equatable, Sendable {
        case addToCalendar(title: String, start: Date, durationMinutes: Int, notes: String)
        case remindDoses
        case call(number: String, label: String)
        case message(OutboxItem)
        /// Opens the prepared order for review; the person sends it.
        case orderSupplies(SupplyOrder)
    }

    public let id: String
    public let icon: String
    public let title: String
    public let detail: String
    public let actionLabel: String
    public let action: Action
}

/// Calm-time behavior: a morning briefing and concrete offers to handle chores before
/// they become emergencies. Pure and deterministic, like the emergency agent.
public enum ProactiveAgent {
    public struct Briefing: Equatable, Sendable {
        public let greeting: String
        public let lines: [String]

        public var spoken: String { ([greeting] + lines).joined(separator: " ") }
    }

    public static func briefing(
        profile: AgentProfile,
        alerts: [(HazardAlert, HazardAssessment)],
        calendar events: [CalendarItem],
        now: Date,
        calendar: Calendar = .current
    ) -> Briefing {
        let hour = calendar.component(.hour, from: now)
        let name = profile.name.split(separator: " ").first.map(String.init) ?? profile.name
        let greeting = hour < 12 ? t("Buenos días, \(name).", "Good morning, \(name).")
            : hour < 19 ? t("Buenas tardes, \(name).", "Good afternoon, \(name).")
            : t("Buenas noches, \(name).", "Good evening, \(name).")

        var lines: [String] = []
        if let top = alerts.first {
            lines.append(top.1.headline + ".")
        } else {
            lines.append(t("Sin alertas cerca de \(profile.approximateLocation.label).", "No alerts near \(profile.approximateLocation.label)."))
        }

        let upcoming = events.filter { $0.end > now && calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        if let next = upcoming.first {
            let place = next.location.isEmpty ? "" : t(" en \(next.location)", " at \(next.location)")
            lines.append(t("Tu agenda: \(next.title)\(place) a las \(time(next.start, calendar)).", "Your next event: \(next.title)\(place) at \(time(next.start, calendar))."))
        }

        for member in profile.household {
            if let block = member.routine.first(where: { $0.weekdays.contains(calendar.component(.weekday, from: now)) && $0.endMinute > minute(of: now, calendar) }) {
                lines.append(t("\(member.name): \(block.place) \(block.hours).", "\(member.name): \(block.place) \(block.hours)."))
            }
        }

        let doses = upcomingDoses(profile: profile, now: now, calendar: calendar)
        if let dose = doses.first {
            lines.append(t("Próxima dosis: \(dose.medication.name) de \(dose.member.name) a las \(time(dose.at, calendar)).",
                           "Next dose: \(dose.member.name)'s \(dose.medication.name) at \(time(dose.at, calendar))."))
        }

        let bagGaps = GoBag.audit(profile.goBag, for: profile, now: now)
        if !bagGaps.isEmpty {
            lines.append(t("Mochila \(GoBag.readiness(profile.goBag, for: profile, now: now))% lista: \(bagGaps.first!.summary).",
                           "Go-bag \(GoBag.readiness(profile.goBag, for: profile, now: now))% ready: \(bagGaps.first!.summary)."))
        } else if let gap = profile.preparedness.gaps.first {
            lines.append(t("Pendiente: \(gap)", "To do: \(gap)"))
        }
        return Briefing(greeting: greeting, lines: lines)
    }

    public struct Dose: Equatable, Sendable {
        public let member: HouseholdMember
        public let medication: Medication
        public let at: Date
    }

    public static func upcomingDoses(profile: AgentProfile, now: Date, within hours: Double = 24, calendar: Calendar = .current) -> [Dose] {
        profile.household.flatMap { member in
            member.medical.medications.compactMap { medication -> Dose? in
                guard let next = medication.nextDose(after: now, calendar: calendar),
                      next.timeIntervalSince(now) <= hours * 3_600 else { return nil }
                return Dose(member: member, medication: medication, at: next)
            }
        }
        .sorted { $0.at < $1.at }
    }

    /// Concrete offers, most important first. Suggestions the person dismissed stay hidden.
    public static func suggestions(
        profile: AgentProfile,
        memory: AgentMemory,
        alerts: [(HazardAlert, HazardAssessment)],
        calendar events: [CalendarItem],
        remindersScheduled: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> [Suggestion] {
        var result: [Suggestion] = []

        // After a real alert that is not yet an emergency: reach the relatives who are away.
        if let (alert, assessment) = alerts.first, assessment.level >= .warning, !memory.emergencyActive {
            for member in profile.household where !member.phone.isEmpty {
                let location = FamilyLocator.likelyLocation(of: member, at: now, homeArea: profile.homeArea, calendar: calendar)
                guard location.place != t("Casa", "Home") || !member.livesWithUser else { continue }
                result.append(Suggestion(
                    id: "alert-checkin:\(alert.eventID):\(member.id.uuidString)",
                    icon: "message.fill",
                    title: t("¿Le escribo a \(member.name)?", "Message \(member.name)?"),
                    detail: t("\(assessment.headline). Debería estar en \(location.description).", "\(assessment.headline). They should be at \(location.description)."),
                    actionLabel: t("Preparar mensaje", "Prepare message"),
                    action: .message(OutboxItem(
                        channel: .whatsapp,
                        recipientName: member.name,
                        phone: member.phone,
                        body: t("\(member.name), ¿estás bien? Hubo un \(assessment.headline.lowercased()). Si puedes, ve a \(location.meetingPoint.isEmpty ? "un lugar seguro" : location.meetingPoint).",
                                "\(member.name), are you OK? There was a \(assessment.headline.lowercased()). If you can, go to \(location.meetingPoint.isEmpty ? "a safe place" : location.meetingPoint)."),
                        createdAt: now
                    ))
                ))
            }
        }

        // Medication running low: book the refill before it becomes an emergency need.
        for member in profile.household {
            for medication in member.medical.medications {
                guard let days = medication.supplyDays, days <= 5 else { continue }
                let tomorrow = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now.addingTimeInterval(86_400)) ?? now
                result.append(Suggestion(
                    id: "refill:\(medication.id.uuidString):\(days)",
                    icon: "pills.fill",
                    title: t("\(medication.name) de \(member.name): quedan \(days) días", "\(member.name)'s \(medication.name): \(days) days left"),
                    detail: member.medical.doctor.isEmpty
                        ? t("Te agendo comprarla mañana a las 10:00.", "I'll schedule buying it tomorrow at 10:00.")
                        : t("Puedo llamar a \(member.medical.doctor) o agendarte la compra.", "I can call \(member.medical.doctor) or schedule the purchase."),
                    actionLabel: t("Agendar compra", "Schedule refill"),
                    action: .addToCalendar(
                        title: t("Comprar \(medication.name) para \(member.name)", "Buy \(medication.name) for \(member.name)"),
                        start: tomorrow,
                        durationMinutes: 30,
                        notes: medication.needsRefrigeration ? t("Necesita refrigeración.", "Needs refrigeration.") : ""
                    )
                ))
                if !member.medical.doctorPhone.isEmpty {
                    result.append(Suggestion(
                        id: "refill-call:\(medication.id.uuidString):\(days)",
                        icon: "phone.fill",
                        title: t("Llamar a \(member.medical.doctor)", "Call \(member.medical.doctor)"),
                        detail: t("Para la receta de \(medication.name).", "For the \(medication.name) prescription."),
                        actionLabel: t("Llamar", "Call"),
                        action: .call(number: member.medical.doctorPhone, label: member.medical.doctor)
                    ))
                }
            }
        }

        // Go-bag: missing, short or expiring items become one prepared order.
        let bagGaps = GoBag.audit(profile.goBag, for: profile, now: now)
        let order = SupplyOrder(gaps: bagGaps)
        if !order.lines.isEmpty {
            let expiring = bagGaps.filter { if case .expiring = $0.problem { return true }; if case .expired = $0.problem { return true }; return false }
            let week = calendar.component(.weekOfYear, from: now)
            result.insert(Suggestion(
                id: "gobag:\(calendar.component(.year, from: now))-\(week):\(order.lines.count)",
                icon: "backpack.fill",
                title: expiring.isEmpty
                    ? t("Mochila: faltan \(order.lines.count) cosas", "Go-bag: \(order.lines.count) items missing")
                    : t("Mochila: \(expiring.count) por vencer, \(order.lines.count) en total", "Go-bag: \(expiring.count) expiring, \(order.lines.count) total"),
                detail: order.lines.prefix(3).map { "\($0.name) ×\($0.quantity)" }.joined(separator: ", "),
                actionLabel: profile.trustedStore == nil ? t("Preparar pedido", "Prepare order") : t("Pedir a \(profile.trustedStore!.name)", "Order from \(profile.trustedStore!.name)"),
                action: .orderSupplies(order)
            ), at: min(result.count, profile.household.contains(where: { $0.medical.medications.contains { ($0.supplyDays ?? 99) <= 5 } }) ? 2 : 0))
        }

        // Dose reminders, once.
        if !remindersScheduled, profile.household.contains(where: { !$0.medical.medications.isEmpty }) {
            let count = profile.household.flatMap(\.medical.medications).reduce(0) { $0 + $1.times.count }
            result.append(Suggestion(
                id: "dose-reminders",
                icon: "bell.badge.fill",
                title: t("Recordatorios de medicamentos", "Medication reminders"),
                detail: t("\(count) dosis diarias. Te aviso a cada hora, también sin internet.", "\(count) daily doses. I'll remind you on time, even offline."),
                actionLabel: t("Activar", "Turn on"),
                action: .remindDoses
            ))
        }

        // A family drill: the single best predictor of a calm response.
        if !profile.household.isEmpty {
            let saturday = nextWeekday(7, hour: 10, after: now, calendar: calendar)
            result.append(Suggestion(
                id: "drill:\(calendar.component(.month, from: now))",
                icon: "figure.run",
                title: t("Simulacro familiar", "Family drill"),
                detail: t("15 minutos para practicar el punto de encuentro (\(profile.meetingPoint)).", "15 minutes to practice your meeting point (\(profile.meetingPoint))."),
                actionLabel: t("Agendar el sábado", "Schedule Saturday"),
                action: .addToCalendar(
                    title: t("Simulacro familiar Faro", "Faro family drill"),
                    start: saturday,
                    durationMinutes: 15,
                    notes: t("Punto de encuentro: \(profile.meetingPoint). Revisar agua, baterías y botiquín.", "Meeting point: \(profile.meetingPoint). Check water, batteries and first aid kit.")
                )
            ))
        }

        // Kit check every three months.
        let quarter = (calendar.component(.month, from: now) - 1) / 3
        if profile.preparedness.score < 100 {
            result.append(Suggestion(
                id: "kit:\(calendar.component(.year, from: now))-\(quarter)",
                icon: "shippingbox.fill",
                title: t("Completar el kit (\(profile.preparedness.score)/100)", "Complete the kit (\(profile.preparedness.score)/100)"),
                detail: profile.preparedness.gaps.prefix(2).joined(separator: " "),
                actionLabel: t("Agendar", "Schedule"),
                action: .addToCalendar(
                    title: t("Completar kit de emergencia", "Complete emergency kit"),
                    start: nextWeekday(1, hour: 11, after: now, calendar: calendar),
                    durationMinutes: 45,
                    notes: profile.preparedness.gaps.joined(separator: "\n")
                )
            ))
        }

        return result.filter { !memory.dismissedKeys.contains($0.id) }
    }

    static func nextWeekday(_ weekday: Int, hour: Int, after date: Date, calendar: Calendar) -> Date {
        let components = DateComponents(hour: hour, minute: 0, weekday: weekday)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }

    static func minute(of date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
