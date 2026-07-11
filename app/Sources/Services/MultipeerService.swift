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

    private var discovered: [MCPeerID] = []
    private var firstSeen: [MCPeerID: Date] = [:]
    private var lastInvite: [MCPeerID: Date] = [:]
    private var retryTimer: Timer?

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
        Log.add("mpc", "start as \(myPeerID.displayName)")
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.retryStalledInvites()
        }
    }

    func stop() {
        Log.add("mpc", "stop")
        retryTimer?.invalidate()
        retryTimer = nil
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        discovered.removeAll()
        firstSeen.removeAll()
        lastInvite.removeAll()
    }

    func send(_ message: PeerMessage, to peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID),
              let data = try? JSONEncoder().encode(message) else { return }
        do {
            try session.send(data, toPeers: [peerID], with: .reliable)
        } catch {
            Log.add("mpc", "send to \(peerID.displayName) failed: \(error.localizedDescription)")
        }
    }

    // The lexicographically-lower name is the designated inviter, which avoids
    // the both-sides-invite race. The higher side still invites as a fallback
    // when nothing has connected for a while — sometimes only one phone's
    // browser ever reports the peer.
    private func isDesignatedInviter(for peerID: MCPeerID) -> Bool {
        myPeerID.displayName < peerID.displayName
    }

    private func invite(_ peerID: MCPeerID, reason: String) {
        lastInvite[peerID] = Date()
        Log.add("mpc", "inviting \(peerID.displayName) (\(reason))")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    private func retryStalledInvites() {
        for peerID in discovered where !session.connectedPeers.contains(peerID) {
            let sinceInvite = Date().timeIntervalSince(lastInvite[peerID] ?? .distantPast)
            guard sinceInvite > 25 else { continue }
            if isDesignatedInviter(for: peerID) {
                invite(peerID, reason: "retry")
            } else if Date().timeIntervalSince(firstSeen[peerID] ?? Date()) > 30 {
                invite(peerID, reason: "fallback — peer never connected to us")
            }
        }
    }
}

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            Log.add("mpc", "found \(peerID.displayName)")
            if !self.discovered.contains(peerID) { self.discovered.append(peerID) }
            if self.firstSeen[peerID] == nil { self.firstSeen[peerID] = Date() }
            self.delegate?.multipeer(self, didDiscover: peerID)
            if self.isDesignatedInviter(for: peerID) {
                self.invite(peerID, reason: "discovered")
            }
        }
    }
    func browser(_ b: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            Log.add("mpc", "lost \(peerID.displayName)")
            self.discovered.removeAll { $0 == peerID }
            self.firstSeen[peerID] = nil
            self.lastInvite[peerID] = nil
            self.delegate?.multipeer(self, didLose: peerID)
        }
    }
    func browser(_ b: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Log.add("mpc", "browse error: \(error.localizedDescription)")
    }
}

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Log.add("mpc", "invitation from \(peerID.displayName) — accepting")
        invitationHandler(true, session)
    }
    func advertiser(_ a: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Log.add("mpc", "advertise error: \(error.localizedDescription)")
    }
}

extension MultipeerService: MCSessionDelegate {
    private func describe(_ s: MCSessionState) -> String {
        switch s {
        case .notConnected: return "notConnected"
        case .connecting:   return "connecting"
        case .connected:    return "connected"
        @unknown default:   return "unknown(\(s.rawValue))"
        }
    }

    func session(_ s: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Log.add("mpc", "\(peerID.displayName) → \(describe(state))")
        DispatchQueue.main.async {
            if state == .notConnected {
                self.lastInvite[peerID] = nil // allow a prompt re-invite
            }
            self.delegate?.multipeer(self, peer: peerID, didChange: state == .connected)
        }
    }
    func session(_ s: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(PeerMessage.self, from: data) else {
            Log.add("mpc", "undecodable message from \(peerID.displayName)")
            return
        }
        DispatchQueue.main.async {
            self.delegate?.multipeer(self, didReceive: msg, from: peerID)
        }
    }
    func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at u: URL?, withError e: Error?) {}
}
