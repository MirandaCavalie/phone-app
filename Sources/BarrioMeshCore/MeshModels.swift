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

    public init(posts: [MeshPost] = [], proposals: [MatchProposal] = []) {
        self.posts = posts
        self.proposals = proposals
    }
}

public struct MeshWireMessage: Codable, Sendable {
    public static let currentProtocolVersion = 1

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
