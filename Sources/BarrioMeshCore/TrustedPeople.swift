import CryptoKit
import Foundation

/// What a person lets their agent share with one trusted person's agent.
public enum TrustScope: String, Codable, CaseIterable, Identifiable, Sendable {
    /// "I'm OK / I need help", sent automatically in an emergency.
    case safety
    /// Where each relative probably is right now, from their routines.
    case whereabouts
    /// Medical cards of the household (conditions, medications, allergies).
    case medical
    /// Their agent answers our requests first and may give without asking us twice.
    case priorityHelp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safety: t("Si estoy bien", "Whether I'm OK")
        case .whereabouts: t("Dónde está mi familia", "Where my family is")
        case .medical: t("Fichas médicas", "Medical cards")
        case .priorityHelp: t("Ayuda prioritaria", "Priority help")
        }
    }

    public var systemImage: String {
        switch self {
        case .safety: "heart.fill"
        case .whereabouts: "mappin.and.ellipse"
        case .medical: "cross.case.fill"
        case .priorityHelp: "hand.raised.fill"
        }
    }

    public static let defaults: Set<TrustScope> = [.safety, .whereabouts, .priorityHelp]
}

/// One side of a trust relationship, kept in the agent's local memory.
public struct TrustedPerson: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// We invited them; waiting for their agent to accept.
        case invited
        /// Both agents agreed.
        case active
        case revoked
    }

    public var id: String { agentID }
    public let agentID: String
    public var name: String
    public var agreementKey: Data
    public var status: Status
    /// What we share with them.
    public var sharing: Set<TrustScope>
    /// What they share with us (from their invite or acceptance).
    public var theyShare: Set<TrustScope>
    public let since: Date
    /// Six digits both phones show; equal codes prove nobody sat in the middle.
    public var pairingCode: String
    public var lastSharedAt: Date?
}

/// The latest snapshot a trusted person's agent sent us, decrypted.
public struct TrustedUpdate: Codable, Equatable, Sendable {
    public struct Relative: Codable, Equatable, Sendable {
        public let name: String
        public let relation: String
        public let location: String?
        public let medical: String?
    }

    public let fromName: String
    public let status: SafetyStatus?
    public let area: String
    public let household: [Relative]
    public let needs: [String]
    public let sentAt: Date
}

/// Agent-to-agent trust protocol messages. Signed like every mesh item; the `share`
/// payload is additionally sealed so only the one recipient can read it.
public struct TrustMessage: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case invite, accept, revoke, share
    }

    public let id: UUID
    public let kind: Kind
    public let from: String
    public let fromName: String
    public let to: String
    /// The sender's X25519 key for sealing shares to them.
    public let agreementKey: Data
    /// invite/accept: what the sender will share. Empty for revoke/share.
    public let scopes: Set<TrustScope>
    /// share: ChaCha20-Poly1305 box of a `TrustedUpdate`.
    public let sealed: Data?
    public let sentAt: Date

    public init(id: UUID = UUID(), kind: Kind, from: String, fromName: String, to: String, agreementKey: Data, scopes: Set<TrustScope> = [], sealed: Data? = nil, sentAt: Date) {
        self.id = id
        self.kind = kind
        self.from = from
        self.fromName = fromName
        self.to = to
        self.agreementKey = agreementKey
        self.scopes = scopes
        self.sealed = sealed
        self.sentAt = sentAt
    }
}

extension AgentIdentity {
    /// X25519 key derived from the signing key, so no second secret has to be stored.
    public var agreementPrivateKey: Curve25519.KeyAgreement.PrivateKey {
        let seed = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: privateKey.rawRepresentation),
            salt: Data("faro-agreement-v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
        let bytes = seed.withUnsafeBytes { Data($0) }
        return (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)) ?? Curve25519.KeyAgreement.PrivateKey()
    }

    public var agreementPublicKey: Data { agreementPrivateKey.publicKey.rawRepresentation }
}

public enum TrustNetwork {
    public static func pairingCode(_ a: Data, _ b: Data) -> String {
        let ordered = [a, b].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = SHA256.hash(data: ordered[0] + ordered[1])
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        return String(format: "%06d", number)
    }

    static func channelKey(mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, ids: [String]) -> SymmetricKey? {
        guard let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs),
              let secret = try? mine.sharedSecretFromKeyAgreement(with: publicKey) else { return nil }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("faro-trust-v1".utf8),
            sharedInfo: Data(ids.sorted().joined(separator: "|").utf8),
            outputByteCount: 32
        )
    }

    public static func seal(_ update: TrustedUpdate, from: String, to person: TrustedPerson, with key: Curve25519.KeyAgreement.PrivateKey) -> Data? {
        guard let channel = channelKey(mine: key, theirs: person.agreementKey, ids: [from, person.agentID]),
              let plain = try? JSONEncoder().encode(update),
              let box = try? ChaChaPoly.seal(plain, using: channel) else { return nil }
        return box.combined
    }

    public static func open(_ message: TrustMessage, me: String, with key: Curve25519.KeyAgreement.PrivateKey) -> TrustedUpdate? {
        guard let sealed = message.sealed,
              let channel = channelKey(mine: key, theirs: message.agreementKey, ids: [me, message.from]),
              let box = try? ChaChaPoly.SealedBox(combined: sealed),
              let plain = try? ChaChaPoly.open(box, using: channel) else { return nil }
        return try? JSONDecoder().decode(TrustedUpdate.self, from: plain)
    }
}
