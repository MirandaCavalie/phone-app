import Foundation

public struct MeshPost: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let authorID: String
    public let authorName: String
    public let kind: PostKind
    public let resource: ResourceKind
    public let quantity: Int
    public let unit: String
    public let urgency: Urgency
    public let area: String
    public let note: String
    public let createdAt: Date
    public let expiresAt: Date
    public var closedAt: Date?

    public init(
        id: UUID = UUID(),
        authorID: String,
        authorName: String,
        kind: PostKind,
        resource: ResourceKind,
        quantity: Int,
        unit: String,
        urgency: Urgency,
        area: String,
        note: String,
        createdAt: Date = Date(),
        expiresAt: Date,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.kind = kind
        self.resource = resource
        self.quantity = max(1, quantity)
        self.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urgency = urgency
        self.area = area.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.closedAt = closedAt
    }

    public func isActive(at date: Date = Date()) -> Bool {
        closedAt == nil && expiresAt > date
    }
}

public struct MatchProposal: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let needID: UUID
    public let offerID: UUID
    public let createdAt: Date
    public var approvals: Set<String>
    public var declines: Set<String>
    public var completions: Set<String>

    public init(
        needID: UUID,
        offerID: UUID,
        createdAt: Date = Date(),
        approvals: Set<String> = [],
        declines: Set<String> = [],
        completions: Set<String> = []
    ) {
        self.id = Self.makeID(needID: needID, offerID: offerID)
        self.needID = needID
        self.offerID = offerID
        self.createdAt = createdAt
        self.approvals = approvals
        self.declines = declines
        self.completions = completions
    }

    public static func makeID(needID: UUID, offerID: UUID) -> String {
        "\(needID.uuidString.lowercased())::\(offerID.uuidString.lowercased())"
    }

    public func merged(with other: MatchProposal) -> MatchProposal {
        precondition(id == other.id, "Only identical proposals can be merged")
        var result = self
        result.approvals.formUnion(other.approvals)
        result.declines.formUnion(other.declines)
        result.completions.formUnion(other.completions)
        return result
    }

    /// Status that also accounts for an agent-to-agent negotiation, when there is one.
    public func status(requiredPeers: Set<String>, negotiation: Negotiation) -> ProposalStatus {
        guard !negotiation.messages.isEmpty else { return status(requiredPeers: requiredPeers) }
        if negotiation.isDeclined || !declines.isEmpty { return .declined }
        if requiredPeers.isSubset(of: completions) { return .completed }
        if negotiation.agreedTerms != nil { return .accepted }
        return .waiting
    }

    public func status(requiredPeers: Set<String>) -> ProposalStatus {
        if !declines.isEmpty { return .declined }
        if requiredPeers.isSubset(of: completions) { return .completed }
        if requiredPeers.isSubset(of: approvals) { return .accepted }
        return approvals.isEmpty ? .suggested : .waiting
    }
}

public enum ProposalStatus: String, Sendable {
    case suggested
    case waiting
    case accepted
    case declined
    case completed

    public var displayName: String {
        switch self {
        case .suggested: "Coincidencia encontrada"
        case .waiting: "Esperando confirmación"
        case .accepted: "Encuentro confirmado"
        case .declined: "Propuesta rechazada"
        case .completed: "Ayuda entregada"
        }
    }
}

public struct MeshState: Codable, Equatable, Sendable {
    public var posts: [MeshPost]
    public var proposals: [MatchProposal]
    public var messages: [AgentMessage]
    public var checkIns: [SafetyCheckIn]

    public init(
        posts: [MeshPost] = [],
        proposals: [MatchProposal] = [],
        messages: [AgentMessage] = [],
        checkIns: [SafetyCheckIn] = []
    ) {
        self.posts = posts
        self.proposals = proposals
        self.messages = messages
        self.checkIns = checkIns
    }

    public init(from decoder: Decoder) throws {
        // Version 1 files on disk have only posts and proposals.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        posts = try container.decodeIfPresent([MeshPost].self, forKey: .posts) ?? []
        proposals = try container.decodeIfPresent([MatchProposal].self, forKey: .proposals) ?? []
        messages = try container.decodeIfPresent([AgentMessage].self, forKey: .messages) ?? []
        checkIns = try container.decodeIfPresent([SafetyCheckIn].self, forKey: .checkIns) ?? []
    }

    public func messages(for proposalID: String) -> [AgentMessage] {
        messages
            .filter { $0.proposalID == proposalID }
            .sorted { ($0.sentAt, $0.id.uuidString) < ($1.sentAt, $1.id.uuidString) }
    }

    public func negotiation(for proposalID: String) -> Negotiation {
        Negotiation(messages: messages(for: proposalID))
    }

    /// The newest check-in of every person in a family circle.
    public func latestCheckIns(circleID: String) -> [SafetyCheckIn] {
        let circle = checkIns.filter { $0.circleID == circleID }
        let newestByAuthor = Dictionary(grouping: circle, by: \.authorID)
            .compactMapValues { $0.max(by: { $0.createdAt < $1.createdAt }) }
        return newestByAuthor.values.sorted { $0.createdAt > $1.createdAt }
    }
}

/// One move in an agent-to-agent negotiation. Messages are immutable and only ever
/// added, so two phones that negotiated while apart converge by set union.
public struct AgentMessage: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case propose
        case counter
        case accept
        case decline
    }

    public let id: UUID
    public let proposalID: String
    public let senderID: String
    public let senderName: String
    public let kind: Kind
    public let terms: MeetingTerms?
    /// For accept/decline: the propose or counter being answered.
    public let respondsTo: UUID?
    public let rationale: String
    public let sentAt: Date

    public init(
        id: UUID = UUID(),
        proposalID: String,
        senderID: String,
        senderName: String,
        kind: Kind,
        terms: MeetingTerms? = nil,
        respondsTo: UUID? = nil,
        rationale: String,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.proposalID = proposalID
        self.senderID = senderID
        self.senderName = senderName
        self.kind = kind
        self.terms = terms
        self.respondsTo = respondsTo
        self.rationale = rationale
        self.sentAt = sentAt
    }
}

public struct MeetingTerms: Codable, Hashable, Sendable {
    public let quantity: Int
    public let meetingPoint: String
    public let meetAt: Date

    public init(quantity: Int, meetingPoint: String, meetAt: Date) {
        self.quantity = max(1, quantity)
        self.meetingPoint = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.meetAt = meetAt
    }
}

public struct Negotiation: Equatable, Sendable {
    public let messages: [AgentMessage]

    public init(messages: [AgentMessage]) {
        self.messages = messages
    }

    /// The latest proposal or counter on the table.
    public var openOffer: AgentMessage? {
        messages.last(where: { $0.kind == .propose || $0.kind == .counter })
    }

    public var isDeclined: Bool {
        messages.contains(where: { $0.kind == .decline })
    }

    /// Terms both sides agreed to: the open offer was accepted by someone other than its sender.
    public var agreedTerms: MeetingTerms? {
        guard !isDeclined, let offer = openOffer else { return nil }
        let accepted = messages.contains {
            $0.kind == .accept && $0.respondsTo == offer.id && $0.senderID != offer.senderID
        }
        return accepted ? offer.terms : nil
    }

    public func hasResponded(_ participantID: String, to offer: AgentMessage) -> Bool {
        messages.contains { $0.senderID == participantID && $0.respondsTo == offer.id }
    }
}

public enum SafetyStatus: String, Codable, CaseIterable, Sendable {
    case safe
    case needsHelp

    public var displayName: String {
        switch self {
        case .safe: "Estoy bien"
        case .needsHelp: "Necesito ayuda"
        }
    }
}

/// A tiny "I'm OK" beacon that hops phone to phone until it reaches the family circle.
public struct SafetyCheckIn: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let authorID: String
    public let authorName: String
    public let circleID: String
    public let status: SafetyStatus
    public let area: String
    public let householdSafe: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        authorID: String,
        authorName: String,
        circleID: String,
        status: SafetyStatus,
        area: String,
        householdSafe: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.circleID = circleID
        self.status = status
        self.area = area
        self.householdSafe = max(0, householdSafe)
        self.createdAt = createdAt
    }
}

public struct MeshWireMessage: Codable, Sendable {
    public static let currentProtocolVersion = 2

    public let protocolVersion: Int
    public let senderID: String
    public let sentAt: Date
    public let state: MeshState

    public init(senderID: String, state: MeshState, sentAt: Date = Date()) {
        self.protocolVersion = Self.currentProtocolVersion
        self.senderID = senderID
        self.sentAt = sentAt
        self.state = state
    }
}
