import Foundation
import NearbyInteraction
import simd

protocol NearbyInteractionManagerDelegate: AnyObject {
    func niManager(_ m: NearbyInteractionManager, didGenerateToken b64: String, forPeer key: String)
    func niManager(_ m: NearbyInteractionManager, didUpdateDistance d: Float?, direction: simd_float3?, forPeer key: String)
}

final class NearbyInteractionManager: NSObject {
    static var isSupported: Bool { NISession.isSupported }

    weak var delegate: NearbyInteractionManagerDelegate?
    private var sessions: [String: NISession] = [:]
    private var peerTokens: [String: NIDiscoveryToken] = [:]
    private var hadDirection: [String: Bool] = [:]

    func start(peerKey: String) {
        guard NISession.isSupported else {
            Log.add("uwb", "NISession not supported on this device")
            return
        }
        Log.add("uwb", "starting session for \(peerKey)")
        let session = NISession()
        session.delegate = self
        sessions[peerKey] = session
        if let token = session.discoveryToken, let b64 = TokenCodec.encode(token) {
            Log.add("uwb", "sending our token to \(peerKey)")
            delegate?.niManager(self, didGenerateToken: b64, forPeer: peerKey)
        } else {
            Log.add("uwb", "no discovery token available for \(peerKey)")
        }
    }

    func receivePeerToken(_ b64: String, forPeer key: String) {
        guard let token = TokenCodec.decode(b64) else {
            Log.add("uwb", "undecodable token from \(key)")
            return
        }
        Log.add("uwb", "received token from \(key)")
        peerTokens[key] = token
        if sessions[key] == nil { start(peerKey: key) } // also emits our token back
        run(peerKey: key)
    }

    private func run(peerKey: String) {
        guard let session = sessions[peerKey], let token = peerTokens[peerKey] else { return }
        Log.add("uwb", "running ranging config for \(peerKey)")
        let config = NINearbyPeerConfiguration(peerToken: token)
        // iOS 16+: config.isCameraAssistanceEnabled = true  // widens direction FOV
        session.run(config)
    }

    func stop(peerKey: String) {
        sessions[peerKey]?.invalidate()
        sessions[peerKey] = nil
        peerTokens[peerKey] = nil
    }

    private func key(for session: NISession) -> String? {
        sessions.first { $0.value === session }?.key
    }
}

extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let key = key(for: session), let obj = nearbyObjects.first else { return }
        let has = obj.direction != nil
        if hadDirection[key] != has {
            hadDirection[key] = has
            Log.add("uwb", "\(key): direction \(has ? "acquired" : "lost")")
        }
        delegate?.niManager(self, didUpdateDistance: obj.distance, direction: obj.direction, forPeer: key)
    }
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                 reason: NINearbyObject.RemovalReason) {
        guard let key = key(for: session) else { return }
        Log.add("uwb", "\(key): peer removed (\(reason == .timeout ? "timeout" : "out of range"))")
        delegate?.niManager(self, didUpdateDistance: nil, direction: nil, forPeer: key)
        if reason == .timeout { run(peerKey: key) }
    }
    func sessionWasSuspended(_ session: NISession) {
        if let k = key(for: session) { Log.add("uwb", "\(k): session suspended") }
    }
    func sessionSuspensionEnded(_ session: NISession) {
        if let k = key(for: session) {
            Log.add("uwb", "\(k): suspension ended, re-running")
            run(peerKey: k)
        }
    }
    func session(_ session: NISession, didInvalidateWith error: Error) {
        let k = key(for: session) ?? "?"
        Log.add("uwb", "\(k): session INVALIDATED: \(error.localizedDescription)")
    }
}

enum TokenCodec {
    static func encode(_ t: NIDiscoveryToken) -> String? {
        (try? NSKeyedArchiver.archivedData(withRootObject: t, requiringSecureCoding: true))?
            .base64EncodedString()
    }
    static func decode(_ b64: String) -> NIDiscoveryToken? {
        guard let d = Data(base64Encoded: b64) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: d)
    }
}
