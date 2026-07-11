import Foundation
import SwiftUI
import CoreLocation
import MultipeerConnectivity
import simd

@MainActor
final class CompassViewModel: NSObject, ObservableObject {
    @Published var peers: [Peer] = []
    @Published var activePeerKey: String?
    @Published var uwbSupported = NearbyInteractionManager.isSupported

    private let mpc = MultipeerService()
    private let ni = NearbyInteractionManager()
    private let location = LocationManager()

    private var peerIDs: [String: MCPeerID] = [:] // key -> MCPeerID for sending
    private var myCoord: CLLocationCoordinate2D?
    private(set) var myHeading: Double = 0
    private var started = false

    override init() {
        super.init()
        mpc.delegate = self
        ni.delegate = self
        location.onLocation = { [weak self] c in self?.handleMyLocation(c) }
        location.onHeading = { [weak self] h in
            self?.myHeading = h
            self?.objectWillChange.send()  // refresh GPS arrow
        }
    }

    func start() {
        guard !started else { return }
        started = true
        mpc.start()
        location.start()
    }

    // MARK: navigation
    func startNavigating(to key: String) {
        activePeerKey = key
        if uwbSupported { ni.start(peerKey: key) } // emits our token via delegate
        sendLocation(to: key)
    }
    func stopNavigating() {
        if let k = activePeerKey { ni.stop(peerKey: k) }
        activePeerKey = nil
    }

    // MARK: GPS
    private func handleMyLocation(_ c: CLLocationCoordinate2D) {
        myCoord = c
        if let k = activePeerKey { sendLocation(to: k) }
        recomputeBearings()
    }
    private func sendLocation(to key: String) {
        guard let c = myCoord, let peerID = peerIDs[key] else { return }
        mpc.send(PeerMessage(kind: .location, lat: c.latitude, lon: c.longitude), to: peerID)
    }
    private func updateGPS(for key: String, lat: Double, lon: Double) {
        guard let i = peers.firstIndex(where: { $0.id == key }) else { return }
        peers[i].lastLat = lat; peers[i].lastLon = lon
        recomputeBearings()
    }
    private func recomputeBearings() {
        guard let me = myCoord else { return }
        for i in peers.indices {
            guard let lat = peers[i].lastLat, let lon = peers[i].lastLon else { continue }
            let p = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            peers[i].absBearing = Geo.bearing(from: me, to: p)
            if peers[i].uwbDirection == nil { // GPS only owns readout when UWB is silent
                peers[i].distance = Float(Geo.distance(from: me, to: p))
                peers[i].source = .gps
            }
        }
    }

    // MARK: arrow
    func arrowAngle(for peer: Peer) -> Double? {
        if let dir = peer.uwbDirection { return Geo.azimuthDegrees(dir) }
        if let bearing = peer.absBearing { return bearing - myHeading }
        return nil
    }

    // MARK: helpers
    private func pretty(_ displayName: String) -> String {
        String(displayName.split(separator: "#").first ?? Substring(displayName))
    }
    private func upsert(_ peerID: MCPeerID, connected: Bool) {
        peerIDs[peerID.displayName] = peerID
        if let i = peers.firstIndex(where: { $0.id == peerID.displayName }) {
            peers[i].connected = connected
        } else {
            peers.append(Peer(id: peerID.displayName, name: pretty(peerID.displayName), connected: connected))
        }
        peers.sort { $0.connected && !$1.connected }
    }
}

extension CompassViewModel: MultipeerServiceDelegate {
    func multipeer(_ s: MultipeerService, didDiscover peerID: MCPeerID) {
        upsert(peerID, connected: false)
    }
    func multipeer(_ s: MultipeerService, didLose peerID: MCPeerID) {
        if let i = peers.firstIndex(where: { $0.id == peerID.displayName }), !peers[i].connected {
            peers.remove(at: i)
        }
    }
    func multipeer(_ s: MultipeerService, peer peerID: MCPeerID, didChange connected: Bool) {
        upsert(peerID, connected: connected)
        if !connected { ni.stop(peerKey: peerID.displayName) }
    }
    func multipeer(_ s: MultipeerService, didReceive message: PeerMessage, from peerID: MCPeerID) {
        let key = peerID.displayName
        switch message.kind {
        case .token:    if let b64 = message.tokenB64 { ni.receivePeerToken(b64, forPeer: key) }
        case .location: if let lat = message.lat, let lon = message.lon { updateGPS(for: key, lat: lat, lon: lon) }
        }
    }
}

extension CompassViewModel: NearbyInteractionManagerDelegate {
    func niManager(_ m: NearbyInteractionManager, didGenerateToken b64: String, forPeer key: String) {
        guard let peerID = peerIDs[key] else { return }
        mpc.send(PeerMessage(kind: .token, tokenB64: b64), to: peerID)
    }
    func niManager(_ m: NearbyInteractionManager, didUpdateDistance d: Float?,
                   direction: simd_float3?, forPeer key: String) {
        guard let i = peers.firstIndex(where: { $0.id == key }) else { return }
        peers[i].uwbDirection = direction
        if let d { peers[i].distance = d; peers[i].source = .uwb }
        if direction == nil && d == nil { peers[i].source = .gps }
    }
}
