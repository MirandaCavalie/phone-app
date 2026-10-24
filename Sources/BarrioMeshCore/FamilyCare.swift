import Foundation

/// What a rescuer or a doctor needs to know in thirty seconds. Stays on the phone;
/// shown on screen, read in the call script and printed in the damage report.
public struct MedicalCard: Codable, Equatable, Sendable {
    public enum Mobility: String, Codable, CaseIterable, Identifiable, Sendable {
        case independent, needsAssistance, wheelchair, bedridden

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .independent: t("Independiente", "Independent")
            case .needsAssistance: t("Necesita ayuda para moverse", "Needs help moving")
            case .wheelchair: t("Silla de ruedas", "Wheelchair")
            case .bedridden: t("En cama", "Bedridden")
            }
        }
    }

    public var birthYear: Int?
    public var bloodType: String
    public var conditions: [String]
    public var allergies: [String]
    public var medications: [Medication]
    public var mobility: Mobility
    /// Oxygen concentrator, CPAP, powered wheelchair…
    public var usesPoweredDevice: Bool
    public var doctor: String
    public var doctorPhone: String
    public var notes: String

    public init(
        birthYear: Int? = nil, bloodType: String = "", conditions: [String] = [], allergies: [String] = [],
        medications: [Medication] = [], mobility: Mobility = .independent, usesPoweredDevice: Bool = false,
        doctor: String = "", doctorPhone: String = "", notes: String = ""
    ) {
        self.birthYear = birthYear
        self.bloodType = bloodType
        self.conditions = conditions
        self.allergies = allergies
        self.medications = medications
        self.mobility = mobility
        self.usesPoweredDevice = usesPoweredDevice
        self.doctor = doctor
        self.doctorPhone = doctorPhone.filter(\.isNumber)
        self.notes = notes
    }

    public var age: Int? {
        birthYear.map { Calendar(identifier: .gregorian).component(.year, from: Date()) - $0 }
    }

    public var isEmpty: Bool {
        birthYear == nil && bloodType.isEmpty && conditions.isEmpty && allergies.isEmpty && medications.isEmpty
            && mobility == .independent && !usesPoweredDevice && doctor.isEmpty && notes.isEmpty
    }

    /// One dense line for the call script and the agent's tools.
    public var summary: String {
        var parts: [String] = []
        if let age { parts.append(t("\(age) años", "\(age) years old")) }
        if !bloodType.isEmpty { parts.append(t("sangre \(bloodType)", "blood type \(bloodType)")) }
        if !conditions.isEmpty { parts.append(conditions.joined(separator: ", ")) }
        if !medications.isEmpty { parts.append(t("toma ", "takes ") + medications.map(\.name).joined(separator: ", ")) }
        if !allergies.isEmpty { parts.append(t("alergia a ", "allergic to ") + allergies.joined(separator: ", ")) }
        if mobility != .independent { parts.append(mobility.displayName.lowercased()) }
        if usesPoweredDevice { parts.append(t("usa un equipo eléctrico", "uses a powered medical device")) }
        return parts.joined(separator: "; ")
    }
}

public struct Medication: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var dose: String
    /// Minutes after midnight for each daily dose.
    public var times: [Int]
    public var needsRefrigeration: Bool
    /// Doses left at home; the agent warns when it runs low.
    public var supplyDays: Int?

    public init(id: UUID = UUID(), name: String, dose: String = "", times: [Int] = [], needsRefrigeration: Bool = false, supplyDays: Int? = nil) {
        self.id = id
        self.name = name
        self.dose = dose
        self.times = times.sorted()
        self.needsRefrigeration = needsRefrigeration
        self.supplyDays = supplyDays
    }

    /// The next dose time after `date`, today or tomorrow.
    public func nextDose(after date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let today = times.first(where: { $0 > minute }) {
            return calendar.date(byAdding: .minute, value: today, to: start)
        }
        guard let first = times.first, let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return calendar.date(byAdding: .minute, value: first, to: tomorrow)
    }
}

/// A recurring place in someone's week: school, work, dialysis, the gym.
public struct RoutineBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var place: String
    public var area: String
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    /// The place's own evacuation or meeting point, if known (a school's patio).
    public var meetingPoint: String

    public init(id: UUID = UUID(), place: String, area: String = "", weekdays: Set<Int>, startMinute: Int, endMinute: Int, meetingPoint: String = "") {
        self.id = id
        self.place = place
        self.area = area
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.meetingPoint = meetingPoint
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
    }

    public var hours: String {
        func format(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
        return "\(format(startMinute))–\(format(endMinute))"
    }
}

/// Where the agent believes a person is right now, and why.
public struct LikelyLocation: Equatable, Sendable {
    public let place: String
    public let area: String
    public let meetingPoint: String
    public let reason: String

    public var description: String {
        var text = place
        if !area.isEmpty { text += " (\(area))" }
        return text
    }
}

public enum FamilyLocator {
    public static func likelyLocation(of member: HouseholdMember, at date: Date, homeArea: String, calendar: Calendar = .current) -> LikelyLocation {
        if let block = member.routine.first(where: { $0.contains(date, calendar: calendar) }) {
            return LikelyLocation(
                place: block.place,
                area: block.area,
                meetingPoint: block.meetingPoint,
                reason: t("según su rutina (\(block.hours))", "per their routine (\(block.hours))")
            )
        }
        if member.livesWithUser {
            return LikelyLocation(place: t("Casa", "Home"), area: homeArea, meetingPoint: "", reason: t("no tiene otra actividad a esta hora", "no other activity at this time"))
        }
        return LikelyLocation(place: t("Desconocido", "Unknown"), area: "", meetingPoint: "", reason: t("vive en otro lugar", "lives elsewhere"))
    }
}
