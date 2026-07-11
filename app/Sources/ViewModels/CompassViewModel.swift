import Foundation
import SwiftUI
import UIKit
import CoreLocation
import MultipeerConnectivity
import simd

struct PeerLocationInfo {
    let coordinate: CLLocationCoordinate2D
    let seenAt: Date?
    let live: Bool
}

@MainActor
final class CompassViewModel: NSObject, ObservableObject {
    private static let nameKey = "displayName"
    private static let findableKey = "findableMode"
    private static let knownKey = "knownPeople"

    @Published var peers: [Peer] = []
    @Published var activePeerKey: String?
    @Published var uwbSupported = NearbyInteractionManager.isSupported
    @Published private(set) var known: [KnownPerson] = []
    @Published private(set) var locationAuthDescription = "not determined"
    @Published private(set) var displayName: String
    @Published var findableMode: Bool {
        didSet {
            UserDefaults.standard.set(findableMode, forKey: Self.findableKey)
            updateBeacon()
        }
    }

    private var mpc: MultipeerService
    private let ni = NearbyInteractionManager()
    private let location = LocationManager()
    private let beacon = FindableBeacon()
    private let scanner = FindableScanner()

    private var peerIDs: [String: MCPeerID] = [:] // key -> MCPeerID for sending
    private var myCoord: CLLocationCoordinate2D?
    var myCoordinate: CLLocationCoordinate2D? { myCoord }
    private(set) var myHeading: Double = 0
    private var started = false

    override init() {
        let storedName = UserDefaults.standard.string(forKey: Self.nameKey)
        let name = storedName ?? UIDevice.current.name
        displayName = name
        findableMode = UserDefaults.standard.bool(forKey: Self.findableKey)
        if let data = UserDefaults.standard.data(forKey: Self.knownKey),
           let list = try? JSONDecoder().decode([KnownPerson].self, from: data) {
            known = list
        }
        mpc = MultipeerService(displayName: name)
        super.init()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Log.add("app", "=== Locompass \(version) launched, I am \"\(name)\", findable=\(findableMode) ===")
        observeLifecycle()
        mpc.delegate = self
        ni.delegate = self
        scanner.delegate = self
        location.onLocation = { [weak self] c in self?.handleMyLocation(c) }
        location.onHeading = { [weak self] h in
            self?.myHeading = h
            self?.objectWillChange.send()  // refresh GPS arrow
        }
        location.onAuth = { [weak self] s in
            self?.locationAuthDescription = LocationManager.describe(s)
        }
    }

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "entered background"),
            (UIApplication.willEnterForegroundNotification, "entering foreground"),
            (UIApplication.willTerminateNotification, "TERMINATING — beacon dies with the app"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "device locked"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "device unlocked"),
        ]
        for (name, message) in events {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Log.add("app", message)
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        mpc.start()
        location.start()
        scanner.start()
        updateBeacon()
    }

    // MARK: identity
    func setDisplayName(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != displayName else { return }
        Log.add("app", "display name → \(name)")
        displayName = name
        UserDefaults.standard.set(name, forKey: Self.nameKey)
        rebuildMPC()
        if findableMode { beacon.start(displayName: name) } // re-advertise new name
    }
    private func rebuildMPC() {
        mpc.stop()
        peers.removeAll { $0.kind == .mpc }
        peerIDs.removeAll()
        mpc = MultipeerService(displayName: displayName)
        mpc.delegate = self
        if started { mpc.start() }
    }

    // MARK: findable mode
    private func updateBeacon() {
        if findableMode {
            beacon.start(displayName: displayName)
            location.setBackgroundUpdates(true)
            location.requestAlways() // survives background suspension far better
            if let c = myCoord { beacon.update(lat: c.latitude, lon: c.longitude) }
        } else {
            beacon.stop()
            location.setBackgroundUpdates(false)
        }
    }

    func requestAlwaysLocation() { location.requestAlways() }

    // MARK: known people (persisted last-seen locations)
    func lastLocation(for name: String) -> PeerLocationInfo? {
        if let p = peers.first(where: { $0.name == name && $0.connected }),
           let lat = p.lastLat, let lon = p.lastLon {
            return PeerLocationInfo(coordinate: .init(latitude: lat, longitude: lon),
                                    seenAt: known.first { $0.name == name }?.seenAt,
                                    live: true)
        }
        if let k = known.first(where: { $0.name == name }), let lat = k.lat, let lon = k.lon {
            return PeerLocationInfo(coordinate: .init(latitude: lat, longitude: lon),
                                    seenAt: k.seenAt, live: false)
        }
        return nil
    }

    func isLive(_ name: String) -> Bool {
        peers.contains { $0.name == name && $0.connected }
    }

    func forget(at offsets: IndexSet) {
        known.remove(atOffsets: offsets)
        persistKnown(force: true)
    }

    private var lastKnownSave = Date.distantPast
    private func remember(name: String, lat: Double? = nil, lon: Double? = nil) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != "Friend…" else { return }
        if let i = known.firstIndex(where: { $0.name == clean }) {
            if let lat, let lon { known[i].lat = lat; known[i].lon = lon }
            known[i].seenAt = Date()
        } else {
            known.append(KnownPerson(name: clean, lat: lat, lon: lon, seenAt: Date()))
        }
        known.sort { $0.seenAt > $1.seenAt }
        persistKnown()
    }
    private func persistKnown(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastKnownSave) > 5 else { return }
        lastKnownSave = Date()
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: Self.knownKey)
        }
    }

    // MARK: navigation
    func startNavigating(to key: String) {
        activePeerKey = key
        guard let peer = peers.first(where: { $0.id == key }) else { return }
        if peer.kind == .mpc {
            if uwbSupported { ni.start(peerKey: key) } // emits our token via delegate
            sendLocation(to: key)
        }
    }
    func stopNavigating() {
        if let k = activePeerKey { ni.stop(peerKey: k) }
        activePeerKey = nil
    }

    // MARK: GPS
    private func handleMyLocation(_ c: CLLocationCoordinate2D) {
        myCoord = c
        if let k = activePeerKey { sendLocation(to: k) }
        if findableMode { beacon.update(lat: c.latitude, lon: c.longitude) }
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
        if connected {
            remember(name: pretty(peerID.displayName))
        } else {
            ni.stop(peerKey: peerID.displayName)
        }
    }
    func multipeer(_ s: MultipeerService, didReceive message: PeerMessage, from peerID: MCPeerID) {
        let key = peerID.displayName
        switch message.kind {
        case .token:    if let b64 = message.tokenB64 { ni.receivePeerToken(b64, forPeer: key) }
        case .location:
            if let lat = message.lat, let lon = message.lon {
                updateGPS(for: key, lat: lat, lon: lon)
                remember(name: pretty(key), lat: lat, lon: lon)
            }
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

extension CompassViewModel: FindableScannerDelegate {
    func scanner(_ s: FindableScanner, didUpdatePeer id: String,
                 name: String?, location loc: BeaconLocation?, rssi: Int?) {
        let key = "ble:" + id
        var index = peers.firstIndex { $0.id == key }
        if index == nil {
            peers.append(Peer(id: key, name: "Friend…", kind: .ble))
            index = peers.count - 1
        }
        guard let i = index else { return }
        peers[i].connected = true
        if let name, !name.isEmpty { peers[i].name = name }
        if let rssi { peers[i].rssi = rssi }
        if let loc { peers[i].lastLat = loc.lat; peers[i].lastLon = loc.lon }
        if let loc {
            remember(name: peers[i].name, lat: loc.lat, lon: loc.lon)
        } else if name != nil {
            remember(name: peers[i].name)
        }
        recomputeBearings()
    }
    func scanner(_ s: FindableScanner, didLosePeer id: String) {
        let key = "ble:" + id
        if let i = peers.firstIndex(where: { $0.id == key }) {
            peers[i].connected = false
            peers[i].rssi = nil
        }
    }
}
