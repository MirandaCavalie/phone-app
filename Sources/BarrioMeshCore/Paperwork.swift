import Foundation

/// The bureaucracy after a disaster, prepared by the agent from what it already knows:
/// a script for the emergency call and a pre-filled damage and needs report.
public enum Paperwork {
    public struct CallScript: Equatable, Sendable {
        public let number: String
        public let lines: [String]

        public var text: String { lines.joined(separator: " ") }
    }

    public struct Report: Equatable, Sendable {
        public struct Section: Equatable, Sendable {
            public let title: String
            public let rows: [String]
        }

        public let title: String
        public let generatedAt: Date
        public let sections: [Section]

        public var plainText: String {
            var text = "\(title)\nGenerado por Faro el \(Paperwork.dateTime(generatedAt))\n"
            for section in sections {
                text += "\n\(section.title.uppercased())\n"
                text += section.rows.map { "• \($0)" }.joined(separator: "\n") + "\n"
            }
            return text
        }
    }

    // MARK: Call

    public static func callScript(profile: AgentProfile, state: MeshState, selfID: String, now: Date) -> CallScript {
        var lines = ["Hola, mi nombre es \(profile.name)."]
        lines.append("Estoy en la zona de \(profile.homeArea), \(profile.country.displayName).")
        if profile.meetingPoint.isEmpty == false {
            lines.append("Un punto de referencia cercano es \(profile.meetingPoint).")
        }
        let people = profile.household.count + 1
        lines.append(people == 1 ? "Estoy solo en casa." : "Somos \(people) personas en el hogar.")

        for member in profile.household where !member.dependsOn.isEmpty {
            let needs = member.dependsOn.map(\.displayName).joined(separator: " y ").lowercased()
            lines.append("Mi \(member.relation), \(member.name), depende de \(needs).")
        }

        let missing = unmetNeeds(profile: profile, state: state, selfID: selfID, now: now)
        if !missing.isEmpty {
            lines.append("Nos falta: \(missing.joined(separator: ", ")).")
        }
        lines.append("No hay heridos que yo sepa. Si eso cambia, lo digo de inmediato.")
        return CallScript(number: profile.country.emergencyNumber, lines: lines)
    }

    // MARK: Report

    public static func report(profile: AgentProfile, memory: AgentMemory, state: MeshState, selfID: String, now: Date) -> Report {
        var sections: [Report.Section] = []

        sections.append(.init(title: "Persona que reporta", rows: [
            "Nombre: \(profile.name)",
            "Zona aproximada: \(profile.homeArea), \(profile.country.displayName)",
            "Contacto de familia: \(profile.familyContacts.map { "\($0.name) (+\($0.phone))" }.joined(separator: ", ").ifEmpty("no registrado"))"
        ]))

        var household = ["\(profile.name) (quien reporta)"]
        household += profile.household.map { member in
            member.dependsOn.isEmpty
                ? "\(member.name), \(member.relation)"
                : "\(member.name), \(member.relation) — depende de \(member.dependsOn.map(\.displayName).joined(separator: " y ").lowercased())"
        }
        sections.append(.init(title: "Hogar (\(household.count) personas)", rows: household))

        var event: [String] = []
        if let started = memory.emergencyStartedAt {
            event.append("Inicio de la emergencia: \(dateTime(started))")
        }
        if let cause = memory.log.last(where: { $0.kind == .mode && $0.title == "Modo emergencia activado" })?.detail {
            event.append("Cómo se detectó: \(cause)")
        }
        let quakes = state.seismicReports.filter { abs($0.detectedAt.timeIntervalSince(memory.emergencyStartedAt ?? now)) < 600 }
        if !quakes.isEmpty {
            let peak = quakes.map(\.peakAcceleration).max() ?? 0
            event.append("Teléfonos cercanos que sintieron el movimiento: \(Set(quakes.map(\.deviceID)).count) (pico \(String(format: "%.2f", peak)) g)")
        }
        sections.append(.init(title: "Evento", rows: event.ifEmpty(["Sin datos del evento."])))

        let missing = unmetNeeds(profile: profile, state: state, selfID: selfID, now: now)
        sections.append(.init(title: "Necesidades sin cubrir", rows: missing.ifEmpty(["Ninguna registrada."])))

        let received = agreements(state: state, selfID: selfID).map { line in
            line.delivered ? "\(line.text) — entregado" : "\(line.text) — acordado"
        }
        sections.append(.init(title: "Ayuda coordinada entre vecinos", rows: received.ifEmpty(["Ninguna todavía."])))

        let timeline = memory.log
            .filter { [.mode, .checkIn, .published, .agreement, .family].contains($0.kind) }
            .reversed()
            .prefix(12)
            .map { "\(time($0.date)) — \($0.title)" }
        sections.append(.init(title: "Cronología", rows: Array(timeline).ifEmpty(["Sin acciones registradas."])))

        sections.append(.init(title: "Nota", rows: [
            "Este reporte lo preparó un agente personal con datos ingresados por la persona. No incluye direcciones exactas.",
            "Revísalo antes de enviarlo a las autoridades, a tu aseguradora o al registro de damnificados de tu país."
        ]))

        return Report(title: "Reporte de afectación del hogar", generatedAt: now, sections: sections)
    }

    // MARK: Helpers

    static func unmetNeeds(profile: AgentProfile, state: MeshState, selfID: String, now: Date) -> [String] {
        state.posts
            .filter { $0.authorID == selfID && $0.kind == .need && $0.isActive(at: now) }
            .compactMap { need in
                let covered = state.proposals
                    .filter { $0.needID == need.id }
                    .compactMap { state.negotiation(for: $0.id).agreedTerms?.quantity }
                    .reduce(0, +)
                let missing = need.quantity - covered
                return missing > 0 ? "\(quantity(missing, need.unit)) de \(need.resource.displayName.lowercased())" : nil
            }
    }

    struct AgreementLine {
        let text: String
        let delivered: Bool
    }

    static func agreements(state: MeshState, selfID: String) -> [AgreementLine] {
        state.proposals.compactMap { proposal in
            guard let terms = state.negotiation(for: proposal.id).agreedTerms,
                  let need = state.posts.first(where: { $0.id == proposal.needID }),
                  let offer = state.posts.first(where: { $0.id == proposal.offerID }),
                  need.authorID == selfID || offer.authorID == selfID else { return nil }
            let text = need.authorID == selfID
                ? "Recibimos \(terms.quantity) \(need.unit) de \(need.resource.displayName.lowercased()) de \(offer.authorName)"
                : "Entregamos \(terms.quantity) \(need.unit) de \(need.resource.displayName.lowercased()) a \(need.authorName)"
            return AgreementLine(text: text, delivered: proposal.completions.contains(selfID))
        }
    }

    /// "1 botella", "3 botellas".
    public static func quantity(_ value: Int, _ unit: String) -> String {
        guard value == 1 else { return "\(value) \(unit)" }
        let singular = unit.hasSuffix("es") && unit.count > 4 && !unit.hasSuffix("tes")
            ? String(unit.dropLast(2))
            : unit.hasSuffix("s") ? String(unit.dropLast()) : unit
        return "1 \(singular)"
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "d 'de' MMMM, HH:mm"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        PersonalAgent.timeFormatter.string(from: date)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

private extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] { isEmpty ? fallback : self }
}
