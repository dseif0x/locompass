import Foundation
import MultipeerConnectivity

protocol MultipeerServiceDelegate: AnyObject {
    func multipeer(_ s: MultipeerService, didDiscover peerID: MCPeerID)
    func multipeer(_ s: MultipeerService, didLose peerID: MCPeerID)
    func multipeer(_ s: MultipeerService, peer peerID: MCPeerID, didChange connected: Bool)
    func multipeer(_ s: MultipeerService, didReceive message: PeerMessage, from peerID: MCPeerID)
}

final class MultipeerService: NSObject {
    /// 1–15 chars, must match NSBonjourServices in Info.plist.
    static let serviceType = "uwbcompass"

    let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    weak var delegate: MultipeerServiceDelegate?

    var connectedPeers: [MCPeerID] { session.connectedPeers }

    init(displayName: String) {
        // Suffix guarantees a unique MCPeerID even if two devices share a name.
        let unique = "\(displayName)#\(UUID().uuidString.prefix(4))"
        myPeerID = MCPeerID(displayName: unique)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func send(_ message: PeerMessage, to peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID),
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [peerID], with: .reliable)
    }
}

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        delegate?.multipeer(self, didDiscover: peerID)
        // Only the lexicographically-lower name initiates, to avoid double invites.
        if myPeerID.displayName < peerID.displayName {
            b.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }
    func browser(_ b: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        delegate?.multipeer(self, didLose: peerID)
    }
    func browser(_ b: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("browse error:", error)
    }
}

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session) // auto-accept (prototype)
    }
}

extension MultipeerService: MCSessionDelegate {
    func session(_ s: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.multipeer(self, peer: peerID, didChange: state == .connected)
        }
    }
    func session(_ s: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.delegate?.multipeer(self, didReceive: msg, from: peerID)
        }
    }
    func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at u: URL?, withError e: Error?) {}
}
