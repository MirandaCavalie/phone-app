import Foundation
import Combine
@preconcurrency import MultipeerConnectivity

// Multipeer Connectivity invokes its Objective-C delegate callbacks on a private
// queue. Every mutation owned by this wrapper is immediately marshalled onto the
// main queue, so the wrapper can safely cross that callback boundary.
final class PeerSession: NSObject, ObservableObject, @unchecked Sendable {
    enum SendError: Error {
        case noConnectedPeers
    }

    @Published private(set) var connectedPeerNames: [String] = []
    @Published private(set) var statusText = t("Buscando teléfonos cercanos", "Looking for nearby phones")
    @Published private(set) var lastError: String?

    var onData: ((Data) -> Void)?
    var onPeerConnected: (() -> Void)?

    private static let serviceType = "barrio-mesh"
    private static let protocolTag = String(MeshWireMessage.currentProtocolVersion)

    private let localPeerID: MCPeerID
    private lazy var session: MCSession = {
        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        return session
    }()
    private lazy var advertiser: MCNearbyServiceAdvertiser = {
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["protocol": Self.protocolTag],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        return advertiser
    }()
    private lazy var browser: MCNearbyServiceBrowser = {
        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        return browser
    }()
    private var invitedPeerNames = Set<String>()

    init(displayName: String) {
        let safeName = String(displayName.prefix(50))
        localPeerID = MCPeerID(displayName: safeName)
        super.init()
    }

    func start() {
        _ = session
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        updateStatus()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        updatePeers()
    }

    func send(_ data: Data) throws {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { throw SendError.noConnectedPeers }
        try session.send(data, toPeers: peers, with: .reliable)
    }

    private func updatePeers() {
        connectedPeerNames = session.connectedPeers.map(\.displayName).sorted()
        updateStatus()
    }

    private func updateStatus() {
        if connectedPeerNames.isEmpty {
            statusText = t("Buscando teléfonos cercanos", "Looking for nearby phones")
        } else if connectedPeerNames.count == 1 {
            statusText = t("1 teléfono conectado", "1 phone connected")
        } else {
            statusText = t("\(connectedPeerNames.count) teléfonos conectados", "\(connectedPeerNames.count) phones connected")
        }
    }
}

extension PeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = t("No se pudo anunciar este teléfono: \(error.localizedDescription)", "Could not advertise this phone: \(error.localizedDescription)")
        }
    }
}

extension PeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["protocol"] == Self.protocolTag else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.localPeerID.displayName < peerID.displayName,
                  !self.session.connectedPeers.contains(peerID),
                  self.invitedPeerNames.insert(peerID.displayName).inserted else { return }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 12)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.invitedPeerNames.remove(peerID.displayName)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = t("No se pudieron buscar teléfonos: \(error.localizedDescription)", "Could not browse for phones: \(error.localizedDescription)")
        }
    }
}

extension PeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePeers()
            if state == .connected {
                self.onPeerConnected?()
            } else if state == .notConnected {
                self.invitedPeerNames.remove(peerID.displayName)
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.onData?(data) }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
