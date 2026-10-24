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
            title: "Modo emergencia activado",
            detail: reason
        ))
        return memory
    }

    public func deactivateEmergency(memory: AgentMemory, now: Date) -> AgentMemory {
        guard memory.emergencyActive else { return memory }
        var memory = memory
        memory.emergencyActive = false
        memory.pending.removeAll()
        memory.record(ActivityEntry(date: now, kind: .mode, title: "Volví al modo normal"))
        return memory
    }

    // MARK: - Step

    public func step(state: MeshState, memory: AgentMemory, connectivity: Connectivity, now: Date) -> AgentStepResult {
        var result = AgentStepResult(memory: memory)

        observeConnectivity(connectivity, result: &result, now: now)

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
            title: "Aprobaste: \(pending.title)",
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
        memory.record(ActivityEntry(date: now, kind: .approval, title: "Descartaste: \(pending.title)"))
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
            title: "Avisé a tu familia: \(status.displayName.lowercased())",
            detail: "Viaja de teléfono en teléfono hasta tu círculo familiar."
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
                    reason: "Se perdió la conexión a internet. Sigo trabajando por Bluetooth con los teléfonos cercanos.",
                    now: now
                )
            }
        case .online:
            let unsent = result.memory.unsentOutbox.count
            if previous == .offline, unsent > 0 {
                result.memory.record(ActivityEntry(
                    date: now,
                    kind: .outbox,
                    title: "Volvió la señal: \(unsent) \(unsent == 1 ? "mensaje listo" : "mensajes listos")",
                    detail: "Preparé tus avisos a la familia. Solo falta que toques enviar."
                ))
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
        )
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
                title: "Avisé a tu familia que estás bien",
                detail: "El aviso salta de teléfono en teléfono hasta tu círculo familiar, sin internet."
            ))
            prepareFamilyMessages(result: &result, now: now)
        } else {
            result.memory.pending.append(PendingApproval(
                id: key,
                createdAt: now,
                title: "Avisar a tu familia que estás bien",
                detail: "Se comparte tu nombre y tu zona aproximada (\(profile.homeArea)) con tu círculo familiar.",
                action: .checkIn(checkIn)
            ))
        }
    }

    private func prepareFamilyMessages(result: inout AgentStepResult, now: Date) {
        let alreadyQueued = Set(result.memory.unsentOutbox.map(\.phone))
        let time = Self.timeFormatter.string(from: now)
        let household = profile.household.isEmpty
            ? ""
            : " Estoy con \(profile.household.map(\.name).joined(separator: ", "))."
        let body = "Estoy bien.\(household) Zona: \(profile.homeArea). Mensaje preparado sin señal a las \(time) por mi agente Faro."

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
                title: "Preparé \(added) \(added == 1 ? "mensaje" : "mensajes") para cuando vuelva la señal",
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
                    note: "Para \(member.name) (\(member.relation))."
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
                note: "Compartido por el agente de \(displayName); el hogar conserva su reserva."
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
            let verb = item.kind == .need ? "Pedí" : "Ofrecí"
            let title = "\(verb) \(item.quantity) \(item.resource.defaultUnit) de \(item.resource.displayName.lowercased())"

            if policy.allowsPublishing(item.kind, resource: item.resource) {
                result.perform(.publish(post, profileKey: item.key), now: now)
                result.memory.record(ActivityEntry(
                    date: now,
                    kind: .published,
                    title: title,
                    detail: item.kind == .need
                        ? "Lo sabía por tu perfil. Busco quién pueda ayudar cerca de \(profile.homeArea)."
                        : "Solo lo que sobra después de la reserva de tu hogar."
                ))
            } else {
                let question = item.kind == .need ? "¿Publico este pedido?" : "¿Ofrezco esto?"
                result.memory.pending.append(PendingApproval(
                    id: item.key,
                    createdAt: now,
                    title: "\(question) \(item.quantity) \(item.resource.defaultUnit) de \(item.resource.displayName.lowercased())",
                    detail: PolicyText.whyAsk(item.resource) + (item.note.isEmpty ? "" : " \(item.note)"),
                    action: .publish(post, profileKey: item.key)
                ))
            }
        }
    }

    // MARK: - Negotiation

    private func negotiate(state: MeshState, result: inout AgentStepResult, now: Date) {
        let candidates = MatchEngine.candidates(in: state.posts, at: now)
        var busyNeeds = Set<UUID>()
        var proposedThisStep = Set<UUID>()

        // Needs that already have a live or agreed negotiation are not re-proposed.
        for candidate in candidates {
            let negotiation = state.negotiation(for: candidate.id)
            if !negotiation.messages.isEmpty, !negotiation.isDeclined {
                busyNeeds.insert(candidate.need.id)
            }
        }

        for candidate in candidates {
            let negotiation = state.negotiation(for: candidate.id)

            if candidate.need.authorID == selfID {
                if negotiation.messages.isEmpty {
                    guard !busyNeeds.contains(candidate.need.id),
                          !proposedThisStep.contains(candidate.need.id),
                          committedQuantity(for: candidate.offer, in: state) < candidate.offer.quantity else { continue }
                    propose(candidate, result: &result, now: now)
                    proposedThisStep.insert(candidate.need.id)
                } else if let offer = negotiation.openOffer,
                          offer.senderID != selfID,
                          negotiation.agreedTerms == nil,
                          !negotiation.isDeclined,
                          !negotiation.hasResponded(selfID, to: offer) {
                    respondAsReceiver(candidate, offer: offer, result: &result, now: now)
                }
            } else if candidate.offer.authorID == selfID {
                guard let offer = negotiation.openOffer,
                      offer.senderID != selfID,
                      negotiation.agreedTerms == nil,
                      !negotiation.isDeclined,
                      !negotiation.hasResponded(selfID, to: offer) else { continue }
                respondAsGiver(candidate, offer: offer, state: state, result: &result, now: now)
            }
        }
    }

    private func propose(_ candidate: MatchCandidate, result: inout AgentStepResult, now: Date) {
        let quantity = min(candidate.need.quantity, candidate.offer.quantity)
        let point = profile.meetingPoint.isEmpty ? "Punto de encuentro de \(candidate.need.area)" : profile.meetingPoint
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
            title: "Le propuse un encuentro al agente de \(candidate.offer.authorName)",
            detail: "\(quantity) \(candidate.need.unit) de \(candidate.need.resource.displayName.lowercased()) en \(point) a las \(Self.timeFormatter.string(from: terms.meetAt))."
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
            rationale: "Ayuda parcial aceptada: es mejor que nada mientras sigo buscando.",
            sentAt: now
        )
        let detail = "\(offer.senderName) puede dar \(terms.quantity) de \(candidate.need.quantity) \(candidate.need.unit) en \(terms.meetingPoint)."

        if policy.allowsAccepting(role: .need, resource: candidate.need.resource, quantity: terms.quantity) {
            result.perform(.send(accept), now: now)
            result.memory.record(ActivityEntry(date: now, kind: .negotiation, title: "Acepté la contraoferta", detail: detail))
        } else {
            askOnce(
                key: "respond:\(offer.id.uuidString)",
                title: "¿Aceptar la contraoferta de \(offer.senderName)?",
                detail: detail,
                action: .send(accept),
                result: &result,
                now: now
            )
        }
    }

    private func respondAsGiver(_ candidate: MatchCandidate, offer: AgentMessage, state: MeshState, result: inout AgentStepResult, now: Date) {
        guard let terms = offer.terms else { return }
        let available = candidate.offer.quantity - committedQuantity(for: candidate.offer, in: state)
        let resource = candidate.offer.resource

        if available <= 0 {
            let decline = AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .decline,
                respondsTo: offer.id,
                rationale: "Todo lo disponible ya está comprometido con otros vecinos.",
                sentAt: now
            )
            result.perform(.send(decline), now: now)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .negotiation,
                title: "Rechacé el pedido de \(offer.senderName)",
                detail: "Ya comprometí todo lo que podías compartir de \(resource.displayName.lowercased())."
            ))
            return
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
                rationale: "Solo \(giving) sin tocar la reserva de tu hogar.",
                sentAt: now
            )
            title = "Contraofrecí \(giving) de \(terms.quantity) a \(offer.senderName)"
        } else {
            response = AgentMessage(
                proposalID: candidate.id,
                senderID: selfID,
                senderName: displayName,
                kind: .accept,
                terms: terms,
                respondsTo: offer.id,
                rationale: "Dentro del límite que autorizaste.",
                sentAt: now
            )
            title = "Acepté darle \(giving) \(candidate.offer.unit) a \(offer.senderName)"
        }
        let detail = "\(resource.displayName) en \(terms.meetingPoint) a las \(Self.timeFormatter.string(from: terms.meetAt))."

        if policy.allowsAccepting(role: .offer, resource: resource, quantity: giving) {
            result.perform(.send(response), now: now)
            result.memory.record(ActivityEntry(date: now, kind: .negotiation, title: title, detail: detail))
        } else {
            askOnce(
                key: "respond:\(offer.id.uuidString)",
                title: "¿Dar \(giving) \(candidate.offer.unit) de \(resource.displayName.lowercased()) a \(offer.senderName)?",
                detail: detail + " " + PolicyText.whyAsk(resource, quantity: giving, limit: policy.autoGiveLimit),
                action: .send(response),
                result: &result,
                now: now
            )
        }
    }

    private func askOnce(key: String, title: String, detail: String, action: AgentAction, result: inout AgentStepResult, now: Date) {
        guard !result.memory.isHandled(key) else { return }
        result.memory.pending.append(PendingApproval(id: key, createdAt: now, title: title, detail: detail, action: action))
    }

    /// Units of an offer already promised in agreed negotiations.
    private func committedQuantity(for offerPost: MeshPost, in state: MeshState) -> Int {
        state.proposals
            .filter { $0.offerID == offerPost.id }
            .compactMap { state.negotiation(for: $0.id).agreedTerms?.quantity }
            .reduce(0, +)
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
            let verb = need.authorID == selfID ? "recibes" : "entregas"
            result.memory.record(ActivityEntry(
                date: now,
                kind: .agreement,
                title: "Acuerdo con \(counterpart)",
                detail: "\(verb.capitalized) \(terms.quantity) \(need.unit) de \(need.resource.displayName.lowercased()) en \(terms.meetingPoint) a las \(Self.timeFormatter.string(from: terms.meetAt))."
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
                title: "¿Se concretó la entrega con \(followUp.counterpartName)?",
                detail: "Ya pasó la hora acordada. Si se hizo, la cierro para que nadie más la espere.",
                action: .complete(proposalID: followUp.proposalID)
            ))
            result.memory.record(ActivityEntry(
                date: now,
                kind: .followUp,
                title: "Seguimiento: encuentro con \(followUp.counterpartName)",
                detail: "Te pregunto si se concretó."
            ))
        }
    }

    private func noticeFamily(state: MeshState, result: inout AgentStepResult, now: Date) {
        guard let circleID = profile.familyCircleID else { return }
        for checkIn in state.latestCheckIns(circleID: circleID)
        where checkIn.authorID != selfID && !result.memory.seenCheckIns.contains(checkIn.id) {
            result.memory.seenCheckIns.insert(checkIn.id)
            result.memory.record(ActivityEntry(
                date: now,
                kind: .family,
                title: "\(checkIn.authorName): \(checkIn.status.displayName.lowercased())",
                detail: "Zona \(checkIn.area) · enviado a las \(Self.timeFormatter.string(from: checkIn.createdAt)). Llegó por la red de teléfonos cercanos."
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
            return "Siempre te pregunto antes de compartir algo de \(resource.displayName.lowercased())."
        }
        if let quantity, quantity > limit {
            return limit == 0
                ? "Me pediste que siempre pregunte antes de comprometer algo."
                : "Supera el límite de \(limit) que me autorizaste."
        }
        return "Tus permisos dicen que te pregunte."
    }
}
