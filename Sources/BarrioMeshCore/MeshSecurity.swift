import CryptoKit
import Foundation

/// A device's long-lived signing identity. The private key never leaves the phone
/// (the app keeps it in the Keychain); peers learn the public key the first time
/// they see a signed item and pin it to that author from then on.
public struct AgentIdentity: Sendable {
    public let privateKey: Curve25519.Signing.PrivateKey

    public init(privateKey: Curve25519.Signing.PrivateKey = .init()) {
        self.privateKey = privateKey
    }

    public init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    /// Self-certifying id: derived from the public key, so nobody can claim it without the key.
    public var agentID: String { MeshSecurity.agentID(for: publicKey) }

    /// A fixed identity for simulated neighbors, stable across launches.
    public static func deterministic(seed: String) -> AgentIdentity {
        let bytes = Data(SHA256.hash(data: Data(("faro-demo|" + seed).utf8)))
        return (try? AgentIdentity(rawRepresentation: bytes)) ?? AgentIdentity()
    }

    /// Short human-checkable fingerprint, e.g. for comparing two phones in person.
    public var fingerprint: String { MeshSecurity.fingerprint(of: publicKey) }

    public func sign(_ itemID: UUID, payload: Data, authorID: String) throws -> ItemSignature {
        ItemSignature(
            itemID: itemID,
            authorID: authorID,
            publicKey: publicKey,
            signature: try privateKey.signature(for: payload)
        )
    }
}

public struct ItemSignature: Codable, Hashable, Identifiable, Sendable {
    public let itemID: UUID
    public let authorID: String
    public let publicKey: Data
    public let signature: Data

    public var id: UUID { itemID }
}

/// Signs what this phone authors and filters what peers send: an item survives only
/// if its author signed exactly those bytes, with the key first seen for that author.
public enum MeshSecurity {
    public struct Verdict: Sendable {
        public let accepted: MeshState
        public let rejected: Int
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: Canonical payloads

    static func payload(_ post: MeshPost) throws -> Data {
        // `closedAt` changes after signing; only the author's original content is covered.
        var copy = post
        copy.closedAt = nil
        return try encoder.encode(copy)
    }

    static func payload<Item: Encodable>(_ item: Item) throws -> Data {
        try encoder.encode(item)
    }

    // MARK: Signing

    /// Signatures for every item in `state` authored by `authorID` that is not yet signed.
    public static func sign(_ state: MeshState, authorID: String, with identity: AgentIdentity) -> [ItemSignature] {
        let signed = Set(state.signatures.map(\.itemID))
        var result: [ItemSignature] = []
        func add(_ id: UUID, _ payload: () throws -> Data) {
            guard !signed.contains(id), let data = try? payload(),
                  let signature = try? identity.sign(id, payload: data, authorID: authorID) else { return }
            result.append(signature)
        }
        for post in state.posts where post.authorID == authorID { add(post.id) { try payload(post) } }
        for message in state.messages where message.senderID == authorID { add(message.id) { try payload(message) } }
        for checkIn in state.checkIns where checkIn.authorID == authorID { add(checkIn.id) { try payload(checkIn) } }
        for report in state.seismicReports where report.deviceID == authorID { add(report.id) { try payload(report) } }
        for alert in state.hazardAlerts where alert.relayedBy == authorID { add(alert.id) { try payload(alert) } }
        return result
    }

    // MARK: Verification

    /// Keeps only correctly signed items from `incoming`: the signature must verify and the
    /// author id must be the one derived from the signing key. No trust-on-first-use window,
    /// so an attacker who reaches a phone first still cannot speak for anyone else.
    public static func verify(_ incoming: MeshState, known: MeshState) -> Verdict {
        let knownIDs = Set(known.posts.map(\.id)).union(known.messages.map(\.id))
            .union(known.checkIns.map(\.id)).union(known.seismicReports.map(\.id)).union(known.hazardAlerts.map(\.id))

        var signatures: [UUID: ItemSignature] = [:]
        for signature in incoming.signatures where agentID(for: signature.publicKey) == signature.authorID {
            signatures[signature.itemID] = signature
        }

        var rejected = 0
        var acceptedSignatures: [ItemSignature] = []
        func valid(_ id: UUID, author: String, _ payload: () throws -> Data) -> Bool {
            if knownIDs.contains(id) { return true }
            guard let signature = signatures[id],
                  signature.authorID == author,
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signature.publicKey),
                  let data = try? payload(),
                  key.isValidSignature(signature.signature, for: data) else {
                rejected += 1
                return false
            }
            acceptedSignatures.append(signature)
            return true
        }

        let posts = incoming.posts.filter { post in valid(post.id, author: post.authorID) { try payload(post) } }
        let messages = incoming.messages.filter { message in valid(message.id, author: message.senderID) { try payload(message) } }
        let checkIns = incoming.checkIns.filter { checkIn in valid(checkIn.id, author: checkIn.authorID) { try payload(checkIn) } }
        let reports = incoming.seismicReports.filter { report in valid(report.id, author: report.deviceID) { try payload(report) } }
        let alerts = incoming.hazardAlerts.filter { alert in valid(alert.id, author: alert.relayedBy) { try payload(alert) } }

        // Approvals and completions are only trusted from the two people a proposal concerns.
        // Full-state gossip resends posts the receiver already has, so ids repeat here.
        let postAuthors = Dictionary((known.posts + posts).map { ($0.id, $0.authorID) }, uniquingKeysWith: { first, _ in first })
        let proposals = incoming.proposals.compactMap { proposal -> MatchProposal? in
            guard let need = postAuthors[proposal.needID], let offer = postAuthors[proposal.offerID] else { return nil }
            let participants: Set<String> = [need, offer]
            var cleaned = proposal
            cleaned.approvals.formIntersection(participants)
            cleaned.declines.formIntersection(participants)
            cleaned.completions.formIntersection(participants)
            return cleaned
        }

        return Verdict(
            accepted: MeshState(
                posts: posts,
                proposals: proposals,
                messages: messages,
                checkIns: checkIns,
                seismicReports: reports,
                signatures: acceptedSignatures,
                hazardAlerts: alerts
            ),
            rejected: rejected
        )
    }

    public static func agentID(for publicKey: Data) -> String {
        "f" + SHA256.hash(data: publicKey).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public static func fingerprint(of publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        return digest.prefix(4).map { String(format: "%02X", $0) }.joined(separator: "-")
    }
}

// MARK: - Encrypted family check-ins

extension FamilyCircle {
    static func normalized(_ code: String) -> String {
        code.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Symmetric key every phone in the family derives from the shared code (HKDF-SHA256).
    static func key(for code: String) -> SymmetricKey? {
        let normalized = normalized(code)
        guard normalized.count >= 4 else { return nil }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalized.utf8)),
            salt: Data("faro-family-v1".utf8),
            info: Data("check-in".utf8),
            outputByteCount: 32
        )
    }

    /// A memorable, high-entropy code: three words and a number.
    public static func suggestCode() -> String {
        let words = [
            "ceiba", "guadua", "colibri", "condor", "cafeto", "araguaney", "frailejon", "orquidea",
            "tucan", "jaguar", "volcan", "cordillera", "manglar", "palmera", "turpial", "guacamaya",
            "mango", "maracuya", "arepa", "cacao", "llano", "paramo", "laguna", "sabana"
        ]
        let picked = words.shuffled().prefix(3)
        return picked.joined(separator: "-") + "-\(Int.random(in: 10...99))"
    }
}

extension SafetyCheckIn {
    private struct Private: Codable {
        let authorName: String
        let status: SafetyStatus
        let area: String
        let householdSafe: Int
    }

    public var isSealed: Bool { sealedPayload != nil }

    /// Encrypts who, how and where with the family key. Relaying phones see only
    /// an opaque circle tag, a random device id and a timestamp.
    public func sealed(withCircleCode code: String) -> SafetyCheckIn? {
        guard let key = FamilyCircle.key(for: code),
              let plain = try? JSONEncoder().encode(Private(authorName: authorName, status: status, area: area, householdSafe: householdSafe)),
              let box = try? ChaChaPoly.seal(plain, using: key, authenticating: Data(id.uuidString.utf8)) else { return nil }
        return SafetyCheckIn(
            id: id, authorID: authorID, authorName: "", circleID: circleID,
            status: .safe, area: "", householdSafe: 0, createdAt: createdAt,
            sealedPayload: box.combined
        )
    }

    /// The readable check-in for someone who knows the family code; nil if it cannot be opened.
    public func opened(withCircleCode code: String) -> SafetyCheckIn? {
        guard let sealedPayload else { return self }
        guard let key = FamilyCircle.key(for: code),
              let box = try? ChaChaPoly.SealedBox(combined: sealedPayload),
              let plain = try? ChaChaPoly.open(box, using: key, authenticating: Data(id.uuidString.utf8)),
              let fields = try? JSONDecoder().decode(Private.self, from: plain) else { return nil }
        return SafetyCheckIn(
            id: id, authorID: authorID, authorName: fields.authorName, circleID: circleID,
            status: fields.status, area: fields.area, householdSafe: fields.householdSafe, createdAt: createdAt
        )
    }
}
