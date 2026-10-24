import Foundation

public enum Connectivity: String, Codable, Sendable {
    case online
    case offline
}

/// Everything the agent remembers between steps. Local to this phone, never broadcast.
public struct AgentMemory: Codable, Equatable, Sendable {
    public var emergencyActive: Bool
    public var emergencyStartedAt: Date?
    /// Profile item key ("need:<id>", "offer:<id>", "dependent:<id>:<resource>") → published post.
    public var publishedFromProfile: [String: UUID]
    public var checkedInAt: Date?
    public var log: [ActivityEntry]
    public var pending: [PendingApproval]
    /// Keys the person explicitly declined, so the agent does not ask again.
    public var dismissedKeys: Set<String>
    public var followUps: [FollowUp]
    public var outbox: [OutboxItem]
    public var seenAgreements: Set<String>
    public var seenCheckIns: Set<UUID>
    public var lastConnectivity: Connectivity?
    /// Official event ids already handled, however many phones relayed them.
    public var seenHazards: Set<String>

    public init() {
        emergencyActive = false
        emergencyStartedAt = nil
        publishedFromProfile = [:]
        checkedInAt = nil
        log = []
        pending = []
        dismissedKeys = []
        followUps = []
        outbox = []
        seenAgreements = []
        seenCheckIns = []
        lastConnectivity = nil
        seenHazards = []
    }

    public init(from decoder: Decoder) throws {
        // Memory saved by an older build keeps working when new fields are added.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emergencyActive = try c.decodeIfPresent(Bool.self, forKey: .emergencyActive) ?? false
        emergencyStartedAt = try c.decodeIfPresent(Date.self, forKey: .emergencyStartedAt)
        publishedFromProfile = try c.decodeIfPresent([String: UUID].self, forKey: .publishedFromProfile) ?? [:]
        checkedInAt = try c.decodeIfPresent(Date.self, forKey: .checkedInAt)
        log = try c.decodeIfPresent([ActivityEntry].self, forKey: .log) ?? []
        pending = try c.decodeIfPresent([PendingApproval].self, forKey: .pending) ?? []
        dismissedKeys = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedKeys) ?? []
        followUps = try c.decodeIfPresent([FollowUp].self, forKey: .followUps) ?? []
        outbox = try c.decodeIfPresent([OutboxItem].self, forKey: .outbox) ?? []
        seenAgreements = try c.decodeIfPresent(Set<String>.self, forKey: .seenAgreements) ?? []
        seenCheckIns = try c.decodeIfPresent(Set<UUID>.self, forKey: .seenCheckIns) ?? []
        lastConnectivity = try c.decodeIfPresent(Connectivity.self, forKey: .lastConnectivity)
        seenHazards = try c.decodeIfPresent(Set<String>.self, forKey: .seenHazards) ?? []
    }

    public var unsentOutbox: [OutboxItem] { outbox.filter { $0.sentAt == nil } }

    mutating func record(_ entry: ActivityEntry) {
        log.insert(entry, at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    func isHandled(_ key: String) -> Bool {
        dismissedKeys.contains(key) || pending.contains(where: { $0.id == key })
    }
}

public struct ActivityEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case mode
        case published
        case negotiation
        case agreement
        case checkIn
        case family
        case followUp
        case approval
        case outbox
        case alert
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let title: String
    public let detail: String

    public init(id: UUID = UUID(), date: Date, kind: Kind, title: String, detail: String = "") {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// Something the agent wants to do but its policy says a person must approve first.
public struct PendingApproval: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let title: String
    public let detail: String
    public let action: AgentAction

    public init(id: String, createdAt: Date, title: String, detail: String, action: AgentAction) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.detail = detail
        self.action = action
    }
}

public enum AgentAction: Codable, Equatable, Sendable {
    case publish(MeshPost, profileKey: String)
    case send(AgentMessage)
    case checkIn(SafetyCheckIn)
    case complete(proposalID: String)
}

public struct FollowUp: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let proposalID: String
    public let dueAt: Date
    public let counterpartName: String
    public var fired: Bool

    public init(proposalID: String, dueAt: Date, counterpartName: String, fired: Bool = false) {
        self.id = "followup:\(proposalID)"
        self.proposalID = proposalID
        self.dueAt = dueAt
        self.counterpartName = counterpartName
        self.fired = fired
    }
}

/// A message prepared without signal, to be handed to SMS or WhatsApp when it returns.
/// The agent never sends it: the person taps send in the system composer.
public struct OutboxItem: Codable, Equatable, Identifiable, Sendable {
    public enum Channel: String, Codable, Sendable {
        case sms
        case whatsapp
    }

    public let id: UUID
    public let channel: Channel
    public let recipientName: String
    public let phone: String
    public let body: String
    public let createdAt: Date
    public var sentAt: Date?

    public init(
        id: UUID = UUID(),
        channel: Channel,
        recipientName: String,
        phone: String,
        body: String,
        createdAt: Date,
        sentAt: Date? = nil
    ) {
        self.id = id
        self.channel = channel
        self.recipientName = recipientName
        self.phone = phone
        self.body = body
        self.createdAt = createdAt
        self.sentAt = sentAt
    }
}

/// What a step decided. The caller writes the shared changes to the mesh store and
/// keeps the new memory; the agent itself never touches the network.
public struct AgentStepResult: Sendable {
    public var posts: [MeshPost] = []
    public var proposals: [MatchProposal] = []
    public var messages: [AgentMessage] = []
    public var checkIns: [SafetyCheckIn] = []
    public var memory: AgentMemory

    public init(memory: AgentMemory) {
        self.memory = memory
    }

    public var changesMesh: Bool {
        !posts.isEmpty || !proposals.isEmpty || !messages.isEmpty || !checkIns.isEmpty
    }

    mutating func perform(_ action: AgentAction, now: Date) {
        switch action {
        case let .publish(post, profileKey):
            posts.append(post)
            memory.publishedFromProfile[profileKey] = post.id
        case let .send(message):
            messages.append(message)
        case let .checkIn(checkIn):
            checkIns.append(checkIn)
            memory.checkedInAt = now
        case .complete:
            break
        }
    }
}

/// The personal agent. A pure, deterministic decision loop: given what it knows about
/// its person, their standing permissions, and the shared neighborhood state, it decides
/// what to publish, negotiate, accept, remind, and prepare — and what to ask about.
public struct PersonalAgent: Sendable {
    public let selfID: String
    public var profile: AgentProfile
    public var policy: AgentPolicy

    public init(selfID: String, profile: AgentProfile, policy: AgentPolicy) {
        self.selfID = selfID
        self.profile = profile
        self.policy = policy
    }

    private var displayName: String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Vecino" : name
    }

    // MARK: - Mode

    public func activateEmergency(memory: AgentMemory, reason: String, now: Date) -> AgentMemory {
        guard !memory.emergencyActive else { return memory }
        var memory = memory
        memory.emergencyActive = true
        memory.emergencyStartedAt = now
        memory.record(ActivityEntry(
            date: now,
            kind: .mode,
            title: t("Modo emergencia activado", "Emergency mode on"),
            detail: reason
        ))
        return memory
    }

    public func deactivateEmergency(memory: AgentMemory, now: Date) -> AgentMemory {
        guard memory.emergencyActive else { return memory }
        var memory = memory
        memory.emergencyActive = false
        memory.pending.removeAll()
        memory.record(ActivityEntry(date: now, kind: .mode, title: t("Volví al modo normal", "Back to normal mode")))
        return memory
    }

    // MARK: - Step

    public func step(state: MeshState, memory: AgentMemory, connectivity: Connectivity, now: Date) -> AgentStepResult {
        var result = AgentStepResult(memory: memory)

        observeConnectivity(connectivity, result: &result, now: now)
        observeSeismicReports(state.seismicReports, result: &result, now: now)
        observeHazardAlerts(state.hazardAlerts, result: &result, now: now)

        if result.memory.emergencyActive {
            checkIn(result: &result, now: now)
            publishFromProfile(state: state, result: &result, now: now)
        }

        // Negotiation also runs outside emergency mode so posts made by hand still get handled.
        negotiate(state: Self.overlay(state, with: result), result: &result, now: now)
        let working = Self.overlay(state, with: result)
        trackAgreements(state: working, result: &result, now: now)
        pruneStalePending(state: working, result: &result)
        fireFollowUps(state: working, result: &result, now: now)
        noticeFamily(state: working, result: &result, now: now)

        return result
    }

    /// The person approved a pending action.
    public func approve(_ pendingID: String, state: MeshState, memory: AgentMemory, now: Date) -> AgentStepResult {
        var result = AgentStepResult(memory: memory)
        guard let index = result.memory.pending.firstIndex(where: { $0.id == pendingID }) else { return result }
        let pending = result.memory.pending.remove(at: index)

        switch pending.action {
        case let .complete(proposalID):
            if var proposal = state.proposals.first(where: { $0.id == proposalID }) {
                proposal.completions.insert(selfID)
                result.proposals.append(proposal)
            }
        case .publish, .send, .checkIn:
            result.perform(pending.action, now: now)
        }

        result.memory.record(ActivityEntry(
            date: now,
            kind: .approval,
            title: t("Aprobaste: \(pending.title)", "You approved: \(pending.title)"),
            detail: pending.detail
        ))
        if case .checkIn = pending.action { prepareFamilyMessages(result: &result, now: now) }
        return result
    }

    public func dismiss(_ pendingID: String, memory: AgentMemory, now: Date) -> AgentMemory {
        var memory = memory
        guard let index = memory.pending.firstIndex(where: { $0.id == pendingID }) else { return memory }
        let pending = memory.pending.remove(at: index)
        memory.dismissedKeys.insert(pendingID)
        memory.record(ActivityEntry(date: now, kind: .approval, title: t("Descartaste: \(pending.title)", "You dismissed: \(pending.title)")))
        return memory
    }

    /// A manual check-in from the person, e.g. switching to "necesito ayuda".
    public func manualCheckIn(_ status: SafetyStatus, memory: AgentMemory, now: Date) -> AgentStepResult {
        var result = AgentStepResult(memory: memory)
        guard let checkIn = makeCheckIn(status: status, now: now) else { return result }
        result.perform(.checkIn(checkIn), now: now)
        result.memory.record(ActivityEntry(
            date: now,
            kind: .checkIn,
            title: t("Avisé a tu familia: \(status.displayName.lowercased())", "Told your family: \(status.displayName)"),
            detail: t("Viaja de teléfono en teléfono, cifrado.", "Hops phone to phone, encrypted.")
        ))
        prepareFamilyMessages(result: &result, now: now)
        return result
    }

    // MARK: - Connectivity

    private func observeConnectivity(_ connectivity: Connectivity, result: inout AgentStepResult, now: Date) {
        let previous = result.memory.lastConnectivity
        result.memory.lastConnectivity = connectivity
        guard previous != connectivity else { return }

        switch connectivity {
        case .offline:
            if policy.activateOnOutage, previous == .online {
                result.memory = activateEmergency(
                    memory: result.memory,
                    reason: t("Se cayó internet. Sigo por Bluetooth.", "Internet is down. Continuing over Bluetooth."),
                    now: now
                )
            }
        case .online:
            let unsent = result.memory.unsentOutbox.count
            if previous == .offline, unsent > 0 {
                result.memory.record(ActivityEntry(
                    date: now,
                    kind: .outbox,
                    title: t("Volvió la señal: \(unsent) \(unsent == 1 ? "mensaje listo" : "mensajes listos")", "Signal is back: \(unsent) \(unsent == 1 ? "message" : "messages") ready"),
                    detail: t("Solo falta que toques enviar.", "Just tap send.")
                ))
            }
        }
    }

    // MARK: - Earthquakes

    public enum SeismicDecision: Equatable, Sendable {
        case ignore
        /// Only this phone felt it: give the person a moment to cancel a false alarm.
        case countdown(seconds: Int)
        /// Several phones felt it: act immediately.
        case activateNow(phones: Int)
    }

    public static let seismicCountdown = 15

    /// What to do when this phone's accelerometer reports shaking.
    public func assessShaking(_ event: SeismicEvent, reports: [SeismicReport], memory: AgentMemory, now: Date) -> SeismicDecision {
        guard policy.activateOnShaking, !memory.emergencyActive else { return .ignore }
        let phones = SeismicCorroboration.devices(near: now, in: reports).union([selfID]).count
        return phones >= 2 ? .activateNow(phones: phones) : .countdown(seconds: Self.seismicCountdown)
    }

    public func activateForEarthquake(_ event: SeismicEvent?, phones: Int, memory: AgentMemory, now: Date) -> AgentMemory {
        var detail = phones >= 2
            ? t("\(phones) teléfonos cercanos lo sintieron.", "\(phones) nearby phones felt it.")
            : t("Lo sintió este teléfono.", "This phone felt it.")
        if let event {
            detail += t(" Movimiento \(event.intensity.displayName) (\(String(format: "%.2f", event.peakAcceleration)) g).", " \(event.intensity.displayName.capitalized) shaking (\(String(format: "%.2f", event.peakAcceleration)) g).")
        }
        return activateEmergency(memory: memory, reason: t("Posible sismo. ", "Possible earthquake. ") + detail, now: now)
    }

    /// Neighbors' phones felt shaking: if at least two did, act even if this phone was on a table.
    private func observeSeismicReports(_ reports: [SeismicReport], result: inout AgentStepResult, now: Date) {
        guard policy.activateOnShaking, !result.memory.emergencyActive else { return }
        let recent = reports.filter { now.timeIntervalSince($0.detectedAt) <= SeismicCorroboration.window && $0.detectedAt <= now.addingTimeInterval(5) }
        let phones = SeismicCorroboration.devices(near: now, in: recent)
        guard phones.count >= 2 else { return }
        result.memory = activateForEarthquake(nil, phones: phones.count, memory: result.memory, now: now)
    }

    // MARK: - Official alerts

    /// Official quake/tsunami alerts, fetched by any phone with internet and relayed over the mesh.
    /// Dangerous ones nearby start emergency mode before the network collapses.
    private func observeHazardAlerts(_ alerts: [HazardAlert], result: inout AgentStepResult, now: Date) {
        let home = profile.isConfigured ? profile.approximateLocation.point : nil
        for alert in alerts.sorted(by: { $0.occurredAt < $1.occurredAt })
        where !result.memory.seenHazards.contains(alert.eventID) && now.timeIntervalSince(alert.occurredAt) < 6 * 3_600 {
            result.memory.seenHazards.insert(alert.eventID)
            let assessment = HazardAssessment.assess(alert, home: home)
            guard assessment.level > .ignore else { continue }

            let source = alert.isSimulated ? t("Simulación", "Simulation") : alert.source
            let relayed = alert.relayedBy == selfID ? "" : t(" Llegó por la red de vecinos.", " Relayed by nearby phones.")
            result.memory.record(ActivityEntry(
                date: now,
                kind: .alert,
                title: assessment.headline,
                detail: "\(source): \(alert.place). \(assessment.advice)\(relayed)"
            ))

            if assessment.level == .danger, policy.activateOnOfficialAlert, !result.memory.emergencyActive {
                result.memory = activateEmergency(
                    memory: result.memory,
                    reason: t("Alerta oficial (\(source)): \(assessment.headline). Me adelanto a la caída de la red.", "Official alert (\(source)): \(assessment.headline). Acting before the network fails."),
                    now: now
                )
            }
        }
    }

    // MARK: - Check-in

    private func makeCheckIn(status: SafetyStatus, now: Date) -> SafetyCheckIn? {
        guard let circleID = profile.familyCircleID else { return nil }
        return SafetyCheckIn(
            authorID: selfID,
            authorName: displayName,
            circleID: circleID,
            status: status,
            area: profile.homeArea,
            householdSafe: profile.household.count + 1,
            createdAt: now
        ).sealed(withCircleCode: profile.familyCircleCode)
    }

    private func checkIn(result: inout AgentStepResult, now: Date) {
        let key = "checkin"
        guard result.memory.checkedInAt == nil,
              !result.memory.isHandled(key),
              let checkIn = makeCheckIn(status: .safe, now: now) else { return }

        if policy.autoCheckIn {
            result.perform(.checkIn(checkIn), now: now)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .checkIn,
                title: t("Avisé a tu familia que estás bien", "Told your family you're OK"),
                detail: t("Viaja de teléfono en teléfono, cifrado.", "Hops phone to phone, encrypted.")
            ))
            prepareFamilyMessages(result: &result, now: now)
        } else {
            result.memory.pending.append(PendingApproval(
                id: key,
                createdAt: now,
                title: t("Avisar a tu familia que estás bien", "Tell your family you're OK"),
                detail: t("Comparte tu nombre y zona (\(profile.homeArea)).", "Shares your name and area (\(profile.homeArea))."),
                action: .checkIn(checkIn)
            ))
        }
    }

    private func prepareFamilyMessages(result: inout AgentStepResult, now: Date) {
        let alreadyQueued = Set(result.memory.unsentOutbox.map(\.phone))
        let time = Self.timeFormatter.string(from: now)
        let household = profile.household.isEmpty
            ? ""
            : t(" Estoy con \(profile.household.map(\.name).joined(separator: ", ")).", " I'm with \(profile.household.map(\.name).joined(separator: ", ")).")
        let body = t("Estoy bien.\(household) Zona: \(profile.homeArea). Escrito sin señal a las \(time) por mi agente Faro.",
                     "I'm OK.\(household) Area: \(profile.homeArea). Written offline at \(time) by my Faro agent.")

        var added = 0
        for contact in profile.familyContacts where !contact.phone.isEmpty && !alreadyQueued.contains(contact.phone) {
            result.memory.outbox.append(OutboxItem(
                channel: .sms,
                recipientName: contact.name,
                phone: contact.phone,
                body: body,
                createdAt: now
            ))
            added += 1
        }
        if added > 0 {
            result.memory.record(ActivityEntry(
                date: now,
                kind: .outbox,
                title: t("\(added) \(added == 1 ? "mensaje listo" : "mensajes listos") para cuando vuelva la señal", "\(added) \(added == 1 ? "message" : "messages") ready for when signal returns"),
                detail: profile.familyContacts.map(\.name).joined(separator: ", ")
            ))
        }
    }

    // MARK: - Publishing

    private struct ProfileItem {
        let key: String
        let kind: PostKind
        let resource: ResourceKind
        let quantity: Int
        let urgency: Urgency
        let note: String
    }

    private var profileItems: [ProfileItem] {
        var items: [ProfileItem] = profile.standingNeeds.map {
            ProfileItem(
                key: "need:\($0.id.uuidString)",
                kind: .need,
                resource: $0.resource,
                quantity: $0.quantity,
                urgency: $0.urgency,
                note: $0.reason
            )
        }

        let explicitNeeds = Set(profile.standingNeeds.map(\.resource))
        for member in profile.household {
            for resource in member.dependsOn where !explicitNeeds.contains(resource) {
                let covered = profile.supplies.contains(where: { $0.resource == resource && $0.quantity > 0 })
                guard !covered else { continue }
                items.append(ProfileItem(
                    key: "dependent:\(member.id.uuidString):\(resource.rawValue)",
                    kind: .need,
                    resource: resource,
                    quantity: 1,
                    urgency: .urgent,
                    note: t("Para \(member.name) (\(member.relation)).", "For \(member.name) (\(member.relation)).")
                ))
            }
        }

        for supply in profile.supplies where supply.shareable > 0 {
            items.append(ProfileItem(
                key: "offer:\(supply.id.uuidString)",
                kind: .offer,
                resource: supply.resource,
                quantity: supply.shareable,
                urgency: .normal,
                note: t("Lo que sobra tras la reserva del hogar.", "Spare after the household reserve.")
            ))
        }
        return items
    }

    private func publishFromProfile(state: MeshState, result: inout AgentStepResult, now: Date) {
        for item in profileItems {
            guard result.memory.publishedFromProfile[item.key] == nil,
                  !result.memory.isHandled(item.key) else { continue }

            let post = MeshPost(
                authorID: selfID,
                authorName: displayName,
                kind: item.kind,
                resource: item.resource,
                quantity: item.quantity,
                unit: item.resource.defaultUnit,
                urgency: item.urgency,
                area: profile.homeArea,
                note: item.note,
                createdAt: now,
                expiresAt: now.addingTimeInterval(6 * 3_600)
            )
            let verb = item.kind == .need ? t("Pedí", "Requested") : t("Ofrecí", "Offered")
            let title = "\(verb) \(item.resource.amount(item.quantity))"

            if policy.allowsPublishing(item.kind, resource: item.resource) {
                result.perform(.publish(post, profileKey: item.key), now: now)
                result.memory.record(ActivityEntry(
                    date: now,
                    kind: .published,
                    title: title,
                    detail: item.kind == .need
                        ? t("Desde tu perfil. Busco ayuda en \(profile.homeArea).", "From your profile. Looking for help in \(profile.homeArea).")
                        : t("Solo lo que sobra de tu reserva.", "Only what's above your reserve.")
                ))
            } else {
                let question = item.kind == .need ? t("¿Pido", "Request") : t("¿Ofrezco", "Offer")
                result.memory.pending.append(PendingApproval(
                    id: item.key,
                    createdAt: now,
                    title: "\(question) \(item.resource.amount(item.quantity))\(t("?", "?"))",
                    detail: PolicyText.whyAsk(item.resource) + (item.note.isEmpty ? "" : " \(item.note)"),
                    action: .publish(post, profileKey: item.key)
                ))
            }
        }
    }

    // MARK: - Negotiation

    /// How long the agent waits for a neighbor's agent before withdrawing and trying someone else.
    public static let negotiationTimeout: TimeInterval = 8 * 60

    private func negotiate(state: MeshState, result: inout AgentStepResult, now: Date) {
        let candidates = MatchEngine.candidates(in: state.posts, at: now)
        // Units this agent commits during this step, so two requests answered together
        // can never promise more than the offer holds.
        var committedNow: [UUID: Int] = [:]
        var proposedThisStep = Set<UUID>()

        withdrawStaleProposals(candidates: candidates, state: state, result: &result, now: now)
        let state = Self.overlay(state, with: result)

        // As receiver: one open negotiation per need; keep asking until the need is covered.
        for candidate in receiverOrder(candidates, state: state, memory: result.memory) {
            let negotiation = state.negotiation(for: candidate.id)
            if let offer = negotiation.openOffer,
               offer.senderID != selfID,
               negotiation.agreedTerms == nil,
               !negotiation.isDeclined,
               !negotiation.hasResponded(selfID, to: offer) {
                respondAsReceiver(candidate, offer: offer, result: &result, now: now)
                continue
            }

            guard negotiation.messages.isEmpty,
                  !proposedThisStep.contains(candidate.need.id),
                  !hasOpenNegotiation(for: candidate.need, in: state) else { continue }
            let remaining = candidate.need.quantity - receivedQuantity(for: candidate.need, in: state)
            let available = candidate.offer.quantity - committedQuantity(for: candidate.offer, in: state, memory: result.memory)
            guard remaining > 0, available > 0 else { continue }
            propose(candidate, quantity: min(remaining, available), alreadyCovered: candidate.need.quantity - remaining, result: &result, now: now)
            proposedThisStep.insert(candidate.need.id)
        }

        // As giver: answer the most vulnerable first — urgency, then who asked earliest.
        let incoming = candidates
            .filter { $0.offer.authorID == selfID }
            .compactMap { candidate -> (MatchCandidate, AgentMessage)? in
                let negotiation = state.negotiation(for: candidate.id)
                guard let offer = negotiation.openOffer,
                      offer.senderID != selfID,
                      negotiation.agreedTerms == nil,
                      !negotiation.isDeclined,
                      !negotiation.hasResponded(selfID, to: offer) else { return nil }
                return (candidate, offer)
            }
            .sorted {
                if $0.0.need.urgency != $1.0.need.urgency { return $0.0.need.urgency.rawValue > $1.0.need.urgency.rawValue }
                return $0.1.sentAt < $1.1.sentAt
            }

        for (candidate, offer) in incoming {
            let alreadyCommitted = committedQuantity(for: candidate.offer, in: state, memory: result.memory) + committedNow[candidate.offer.id, default: 0]
            let given = respondAsGiver(candidate, offer: offer, available: candidate.offer.quantity - alreadyCommitted, prioritized: incoming.count > 1, result: &result, now: now)
            committedNow[candidate.offer.id, default: 0] += given
        }
    }

    /// Orders this agent's own matches so neighbors do not all pile onto the same giver:
    /// first offers that can cover the whole need, then the least contested ones, then a
    /// per-need pseudo-random tiebreak so different agents spread out.
    private func receiverOrder(_ candidates: [MatchCandidate], state: MeshState, memory: AgentMemory) -> [MatchCandidate] {
        let mine = candidates.filter { $0.need.authorID == selfID }
        var contested: [UUID: Int] = [:]
        for proposal in state.proposals {
            let negotiation = state.negotiation(for: proposal.id)
            if !negotiation.messages.isEmpty, !negotiation.isDeclined, negotiation.agreedTerms == nil {
                contested[proposal.offerID, default: 0] += 1
            }
        }
        func key(_ candidate: MatchCandidate) -> (Int, Int, Int, UInt64) {
            let available = candidate.offer.quantity - committedQuantity(for: candidate.offer, in: state, memory: memory)
            let remaining = candidate.need.quantity - receivedQuantity(for: candidate.need, in: state)
            return (
                -candidate.need.urgency.rawValue,
                available >= remaining ? 0 : 1,
                contested[candidate.offer.id, default: 0],
                Self.spread(candidate.need.id, candidate.offer.id)
            )
        }
        return mine.sorted { key($0) < key($1) }
    }

    static func spread(_ a: UUID, _ b: UUID) -> UInt64 {
        (a.uuidString + b.uuidString).utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// Proposals this agent sent that nobody answered in time are withdrawn, freeing the need.
    private func withdrawStaleProposals(candidates: [MatchCandidate], state: MeshState, result: inout AgentStepResult, now: Date) {
        for candidate in candidates where candidate.need.authorID == selfID {
            let negotiation = state.negotiation(for: candidate.id)
            guard let offer = negotiation.openOffer,
                  offer.senderID == selfID,
                  negotiation.agreedTerms == nil,
                  !negotiation.isDeclined,
                  now.timeIntervalSince(offer.sentAt) >= Self.negotiationTimeout else { continue }
            result.perform(.send(AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .decline,
                respondsTo: offer.id,
                rationale: t("Sin respuesta a tiempo.", "No answer in time."),
                sentAt: now
            )), now: now)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .negotiation,
                title: t("\(candidate.offer.authorName) no respondió", "\(candidate.offer.authorName) didn't answer"),
                detail: t("Busco \(candidate.need.resource.displayName.lowercased()) con otros vecinos.", "Trying other neighbors for \(candidate.need.resource.displayName.lowercased()).")
            ))
        }
    }

    private func hasOpenNegotiation(for need: MeshPost, in state: MeshState) -> Bool {
        state.proposals.contains { proposal in
            guard proposal.needID == need.id else { return false }
            let negotiation = state.negotiation(for: proposal.id)
            return !negotiation.messages.isEmpty && !negotiation.isDeclined && negotiation.agreedTerms == nil
        }
    }

    /// Units of a need already secured in agreed negotiations.
    private func receivedQuantity(for need: MeshPost, in state: MeshState) -> Int {
        state.proposals
            .filter { $0.needID == need.id }
            .compactMap { state.negotiation(for: $0.id).agreedTerms?.quantity }
            .reduce(0, +)
    }

    private func propose(_ candidate: MatchCandidate, quantity: Int, alreadyCovered: Int, result: inout AgentStepResult, now: Date) {
        let point = profile.meetingPoint.isEmpty ? t("Punto de encuentro de \(candidate.need.area)", "\(candidate.need.area) meeting point") : profile.meetingPoint
        let terms = MeetingTerms(quantity: quantity, meetingPoint: point, meetAt: Self.nextSlot(after: now, minutes: 30))
        let message = AgentMessage(
            proposalID: candidate.id,
            senderID: selfID,
            senderName: displayName,
            kind: .propose,
            terms: terms,
            rationale: "\(candidate.need.resource.displayName) · \(candidate.reason)",
            sentAt: now
        )
        result.proposals.append(MatchProposal(needID: candidate.need.id, offerID: candidate.offer.id, createdAt: now))
        result.perform(.send(message), now: now)
        result.memory.record(ActivityEntry(
            date: now,
            kind: .negotiation,
            title: t("Propuse un encuentro a \(candidate.offer.authorName)", "Proposed a handoff to \(candidate.offer.authorName)"),
            detail: "\(candidate.need.resource.amount(quantity)) · \(point) · \(Self.timeFormatter.string(from: terms.meetAt))"
                + (alreadyCovered > 0 ? t(" (ya tienes \(alreadyCovered))", " (\(alreadyCovered) already secured)") : "")
        ))
    }

    private func respondAsReceiver(_ candidate: MatchCandidate, offer: AgentMessage, result: inout AgentStepResult, now: Date) {
        guard let terms = offer.terms else { return }
        let accept = AgentMessage(
            proposalID: candidate.id,
            senderID: selfID,
            senderName: displayName,
            kind: .accept,
            terms: terms,
            respondsTo: offer.id,
            rationale: t("Ayuda parcial aceptada.", "Partial help accepted."),
            sentAt: now
        )
        let detail = t("\(offer.senderName) puede dar \(terms.quantity) de \(candidate.need.quantity) · \(terms.meetingPoint)", "\(offer.senderName) can give \(terms.quantity) of \(candidate.need.quantity) · \(terms.meetingPoint)")

        if policy.allowsAccepting(role: .need, resource: candidate.need.resource, quantity: terms.quantity) {
            result.perform(.send(accept), now: now)
            result.memory.record(ActivityEntry(date: now, kind: .negotiation, title: t("Acepté la contraoferta", "Accepted the counteroffer"), detail: detail))
        } else {
            askOnce(
                key: "respond:\(offer.id.uuidString)",
                title: t("¿Aceptar la contraoferta de \(offer.senderName)?", "Accept \(offer.senderName)'s counteroffer?"),
                detail: detail,
                action: .send(accept),
                result: &result,
                now: now
            )
        }
    }

    /// Answers one request and returns how many units it committed.
    private func respondAsGiver(
        _ candidate: MatchCandidate,
        offer: AgentMessage,
        available: Int,
        prioritized: Bool,
        result: inout AgentStepResult,
        now: Date
    ) -> Int {
        guard let terms = offer.terms else { return 0 }
        let resource = candidate.offer.resource

        if available <= 0 {
            result.perform(.send(AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .decline,
                respondsTo: offer.id,
                rationale: t("Todo ya está comprometido.", "Everything is already promised."),
                sentAt: now
            )), now: now)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .negotiation,
                title: t("Rechacé el pedido de \(offer.senderName)", "Declined \(offer.senderName)'s request"),
                detail: prioritized
                    ? t("Ya comprometí tu \(resource.displayName.lowercased()), priorizando lo urgente.", "Your \(resource.displayName.lowercased()) is already promised; urgent requests first.")
                    : t("Ya comprometí tu \(resource.displayName.lowercased()).", "Your \(resource.displayName.lowercased()) is already promised.")
            ))
            return 0
        }

        let giving = min(terms.quantity, available)
        let response: AgentMessage
        let title: String
        if giving < terms.quantity {
            response = AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .counter,
                terms: MeetingTerms(quantity: giving, meetingPoint: terms.meetingPoint, meetAt: terms.meetAt),
                respondsTo: offer.id,
                rationale: t("Solo \(giving) sin tocar tu reserva.", "Only \(giving) without touching your reserve."),
                sentAt: now
            )
            title = t("Contraofrecí \(giving) de \(terms.quantity) a \(offer.senderName)", "Countered \(offer.senderName): \(giving) of \(terms.quantity)")
        } else {
            response = AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .accept,
                terms: terms,
                respondsTo: offer.id,
                rationale: t("Dentro de tu límite.", "Within your limit."),
                sentAt: now
            )
            title = t("Acepté darle \(resource.count(giving)) a \(offer.senderName)", "Agreed to give \(offer.senderName) \(resource.count(giving))")
        }
        var detail = "\(resource.displayName) · \(terms.meetingPoint) · \(Self.timeFormatter.string(from: terms.meetAt))"
        if prioritized, candidate.need.urgency == .urgent {
            detail += t(" · primero por ser urgente", " · served first, urgent")
        }

        if policy.allowsAccepting(role: .offer, resource: resource, quantity: giving) {
            result.perform(.send(response), now: now)
            result.memory.record(ActivityEntry(date: now, kind: .negotiation, title: title, detail: detail))
            return giving
        }
        askOnce(
            key: "respond:\(offer.id.uuidString)",
            title: t("¿Dar \(resource.amount(giving)) a \(offer.senderName)?", "Give \(offer.senderName) \(resource.amount(giving))?"),
            detail: detail + " " + PolicyText.whyAsk(resource, quantity: giving, limit: policy.autoGiveLimit),
            action: .send(response),
            result: &result,
            now: now
        )
        // Reserve the units while the person decides, so nothing else is promised meanwhile.
        return giving
    }

    private func askOnce(key: String, title: String, detail: String, action: AgentAction, result: inout AgentStepResult, now: Date) {
        guard !result.memory.isHandled(key) else { return }
        result.memory.pending.append(PendingApproval(id: key, createdAt: now, title: title, detail: detail, action: action))
    }

    /// Units of an offer already spoken for: agreed handoffs, counters its author sent that are
    /// still awaiting an answer, and answers waiting for the person's approval.
    private func committedQuantity(for offerPost: MeshPost, in state: MeshState, memory: AgentMemory) -> Int {
        let proposals = state.proposals.filter { $0.offerID == offerPost.id }
        let agreedOrOffered = proposals.compactMap { proposal -> Int? in
            let negotiation = state.negotiation(for: proposal.id)
            if let agreed = negotiation.agreedTerms { return agreed.quantity }
            guard !negotiation.isDeclined, let open = negotiation.openOffer, open.senderID == offerPost.authorID else { return nil }
            return open.terms?.quantity
        }
        let proposalIDs = Set(proposals.map(\.id))
        let awaitingApproval = memory.pending.compactMap { pending -> Int? in
            guard case let .send(message) = pending.action, proposalIDs.contains(message.proposalID),
                  message.kind == .accept || message.kind == .counter else { return nil }
            return message.terms?.quantity
        }
        return (agreedOrOffered + awaitingApproval).reduce(0, +)
    }

    // MARK: - Agreements and follow-ups

    private func trackAgreements(state: MeshState, result: inout AgentStepResult, now: Date) {
        let proposalIDs = Set(state.messages.map(\.proposalID))
        for proposalID in proposalIDs where !result.memory.seenAgreements.contains(proposalID) {
            guard let terms = state.negotiation(for: proposalID).agreedTerms,
                  let proposal = state.proposals.first(where: { $0.id == proposalID }),
                  let need = state.posts.first(where: { $0.id == proposal.needID }),
                  let offer = state.posts.first(where: { $0.id == proposal.offerID }),
                  need.authorID == selfID || offer.authorID == selfID else { continue }

            result.memory.seenAgreements.insert(proposalID)
            let counterpart = need.authorID == selfID ? offer.authorName : need.authorName
            let verb = need.authorID == selfID ? t("Recibes", "You get") : t("Entregas", "You give")
            result.memory.record(ActivityEntry(
                date: now,
                kind: .agreement,
                title: t("Acuerdo con \(counterpart)", "Deal with \(counterpart)"),
                detail: "\(verb) \(need.resource.amount(terms.quantity)) · \(terms.meetingPoint) · \(Self.timeFormatter.string(from: terms.meetAt))"
            ))
            result.memory.followUps.append(FollowUp(
                proposalID: proposalID,
                dueAt: terms.meetAt.addingTimeInterval(15 * 60),
                counterpartName: counterpart
            ))
        }
    }

    /// Drops questions about offers that were answered or superseded elsewhere.
    private func pruneStalePending(state: MeshState, result: inout AgentStepResult) {
        result.memory.pending.removeAll { pending in
            guard case let .send(message) = pending.action, let answered = message.respondsTo else { return false }
            let negotiation = state.negotiation(for: message.proposalID)
            return negotiation.isDeclined
                || negotiation.agreedTerms != nil
                || negotiation.openOffer?.id != answered
        }
    }

    private func fireFollowUps(state: MeshState, result: inout AgentStepResult, now: Date) {
        for index in result.memory.followUps.indices {
            let followUp = result.memory.followUps[index]
            guard !followUp.fired, followUp.dueAt <= now else { continue }
            result.memory.followUps[index].fired = true

            let completed = state.proposals.first(where: { $0.id == followUp.proposalID })?.completions.contains(selfID) == true
            guard !completed else { continue }

            result.memory.pending.append(PendingApproval(
                id: followUp.id,
                createdAt: now,
                title: t("¿Se hizo la entrega con \(followUp.counterpartName)?", "Did the handoff with \(followUp.counterpartName) happen?"),
                detail: t("Ya pasó la hora acordada.", "The agreed time has passed."),
                action: .complete(proposalID: followUp.proposalID)
            ))
            result.memory.record(ActivityEntry(
                date: now,
                kind: .followUp,
                title: t("Seguimiento con \(followUp.counterpartName)", "Follow-up with \(followUp.counterpartName)"),
                detail: t("Te pregunto si se hizo.", "Asking if it happened.")
            ))
        }
    }

    private func noticeFamily(state: MeshState, result: inout AgentStepResult, now: Date) {
        for checkIn in state.latestCheckIns(circleCode: profile.familyCircleCode)
        where checkIn.authorID != selfID && !result.memory.seenCheckIns.contains(checkIn.id) {
            result.memory.seenCheckIns.insert(checkIn.id)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .family,
                title: "\(checkIn.authorName): \(checkIn.status.displayName.lowercased())",
                detail: "\(checkIn.area) · \(Self.timeFormatter.string(from: checkIn.createdAt)) · \(t("por la red de vecinos", "via nearby phones"))"
            ))
        }
    }

    // MARK: - Helpers

    /// The shared state as it will look once this step's decisions are applied.
    static func overlay(_ state: MeshState, with result: AgentStepResult) -> MeshState {
        let store = MeshStore(initialState: state)
        store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns)
        return store.state
    }

    static func nextSlot(after date: Date, minutes: Int) -> Date {
        let target = date.addingTimeInterval(TimeInterval(minutes * 60))
        let step: TimeInterval = 5 * 60
        return Date(timeIntervalSince1970: (target.timeIntervalSince1970 / step).rounded(.up) * step)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum PolicyText {
    static func whyAsk(_ resource: ResourceKind, quantity: Int? = nil, limit: Int = 0) -> String {
        if AgentPolicy.alwaysAskResources.contains(resource) {
            return t("Siempre pregunto por \(resource.displayName.lowercased()).", "I always ask about \(resource.displayName.lowercased()).")
        }
        if let quantity, quantity > limit {
            return limit == 0
                ? t("Me pediste preguntar siempre.", "You asked me to always check.")
                : t("Supera tu límite de \(limit).", "Above your limit of \(limit).")
        }
        return t("Tus permisos piden preguntar.", "Your permissions say to ask.")
    }
}
