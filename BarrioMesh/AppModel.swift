import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    struct MatchSummary: Identifiable {
        let candidate: MatchCandidate
        let proposal: MatchProposal?
        let status: ProposalStatus

        var id: String { candidate.id }
        var requiredPeers: Set<String> { [candidate.need.authorID, candidate.offer.authorID] }
    }

    @Published private(set) var meshState: MeshState
    @Published private(set) var lastSyncAt: Date?
    @Published var alertMessage: String?
    @Published var displayName: String {
        didSet {
            let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            UserDefaults.standard.set(cleaned, forKey: Self.displayNameKey)
        }
    }

    let deviceID: String
    let peerSession: PeerSession

    private let store: MeshStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = existing
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: Self.deviceIDKey)
            deviceID = created
        }

        displayName = defaults.string(forKey: Self.displayNameKey)
            ?? UIDevice.current.name.replacingOccurrences(of: "’s iPhone", with: "")

        let stateURL = Self.applicationSupportURL.appendingPathComponent("mesh-state.json")
        store = MeshStore(fileURL: stateURL)
        meshState = store.state

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let suffix = String(deviceID.prefix(4))
        peerSession = PeerSession(displayName: "\(displayName)-\(suffix)")
        peerSession.onData = { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        peerSession.onPeerConnected = { [weak self] in
            Task { @MainActor in self?.broadcastState() }
        }
        peerSession.start()
    }

    var activeNeeds: [MeshPost] {
        activePosts.filter { $0.kind == .need }
    }

    var activeOffers: [MeshPost] {
        activePosts.filter { $0.kind == .offer }
    }

    var activePosts: [MeshPost] {
        meshState.posts
            .filter { $0.isActive() }
            .sorted {
                if $0.urgency == $1.urgency { return $0.createdAt > $1.createdAt }
                return $0.urgency.rawValue > $1.urgency.rawValue
            }
    }

    var matchSummaries: [MatchSummary] {
        MatchEngine.candidates(in: meshState.posts).map { candidate in
            let proposal = meshState.proposals.first(where: { $0.id == candidate.id })
            let required: Set<String> = [candidate.need.authorID, candidate.offer.authorID]
            return MatchSummary(
                candidate: candidate,
                proposal: proposal,
                status: proposal?.status(requiredPeers: required) ?? .suggested
            )
        }
        .filter { $0.status != .declined }
    }

    func addPost(
        kind: PostKind,
        resource: ResourceKind,
        quantity: Int,
        unit: String,
        urgency: Urgency,
        area: String,
        note: String,
        expiresIn: TimeInterval
    ) {
        let post = MeshPost(
            authorID: deviceID,
            authorName: sanitizedDisplayName,
            kind: kind,
            resource: resource,
            quantity: quantity,
            unit: unit.isEmpty ? resource.defaultUnit : unit,
            urgency: urgency,
            area: area,
            note: note,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        guard store.add(post) else { return }
        publishChange()
    }

    func close(_ post: MeshPost) {
        guard post.authorID == deviceID, store.closePost(id: post.id) else { return }
        publishChange()
    }

    func approve(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID) else { return }
        var proposal = summary.proposal ?? MatchProposal(
            needID: summary.candidate.need.id,
            offerID: summary.candidate.offer.id
        )
        proposal.approvals.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func decline(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID) else { return }
        var proposal = summary.proposal ?? MatchProposal(
            needID: summary.candidate.need.id,
            offerID: summary.candidate.offer.id
        )
        proposal.declines.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func complete(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID), var proposal = summary.proposal else { return }
        proposal.completions.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func hasApproved(_ summary: MatchSummary) -> Bool {
        summary.proposal?.approvals.contains(deviceID) == true
    }

    func hasCompleted(_ summary: MatchSummary) -> Bool {
        summary.proposal?.completions.contains(deviceID) == true
    }

    func resetLocalData() {
        store.reset()
        meshState = store.state
        broadcastState()
    }

    func loadDemoData() {
        let now = Date()
        let demoNeed = MeshPost(
            authorID: "demo-ana",
            authorName: "Ana",
            kind: .need,
            resource: .power,
            quantity: 1,
            unit: "carga",
            urgency: .urgent,
            area: "Mission",
            note: "Necesito cargar el teléfono para contactar a mi familia.",
            createdAt: now.addingTimeInterval(-240),
            expiresAt: now.addingTimeInterval(7_200)
        )
        let demoOffer = MeshPost(
            authorID: "demo-luis",
            authorName: "Luis",
            kind: .offer,
            resource: .power,
            quantity: 3,
            unit: "cargas",
            urgency: .normal,
            area: "Mission",
            note: "Tengo un power bank disponible.",
            createdAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(7_200)
        )
        _ = store.add(demoNeed)
        _ = store.add(demoOffer)
        publishChange()
    }

    private func receive(_ data: Data) {
        do {
            let message = try decoder.decode(MeshWireMessage.self, from: data)
            guard message.protocolVersion == MeshWireMessage.currentProtocolVersion else {
                alertMessage = "Un teléfono cercano usa una versión incompatible."
                return
            }
            if store.merge(message.state) {
                meshState = store.state
                lastSyncAt = Date()
                // Gossip only converges when newly learned state is relayed onward.
                broadcastState()
            }
        } catch {
            alertMessage = "No se pudo leer un mensaje de la red local."
        }
    }

    private func publishChange() {
        meshState = store.state
        broadcastState()
    }

    private func broadcastState() {
        do {
            let message = MeshWireMessage(senderID: deviceID, state: meshState)
            try peerSession.send(encoder.encode(message))
        } catch PeerSession.SendError.noConnectedPeers {
            // Offline-first: state stays queued locally until a peer connects.
        } catch {
            alertMessage = "La información quedó guardada, pero aún no pudo enviarse."
        }
    }

    private var sanitizedDisplayName: String {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Vecino" : cleaned
    }

    private static let deviceIDKey = "barrio-mesh.device-id"
    private static let displayNameKey = "barrio-mesh.display-name"

    private static var applicationSupportURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("BarrioMesh", isDirectory: true)
    }
}
