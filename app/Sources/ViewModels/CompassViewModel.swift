import Foundation
import SwiftUI
import UIKit
import CoreLocation
import MultipeerConnectivity
import UserNotifications
import simd

struct PeerLocationInfo {
    let coordinate: CLLocationCoordinate2D
    let seenAt: Date?
    let live: Bool
}

@MainActor
final class CompassViewModel: NSObject, ObservableObject {
    static let shared = CompassViewModel()

    private static let nameKey = "displayName"
    private static let findableKey = "findableMode"
    private static let knownKey = "knownPeople"
    private static let chatsKey = "chats"
    private static let seenChatKey = "seenChatIds"

    @Published var peers: [Peer] = []
    @Published var activePersonName: String?
    @Published var uwbSupported = NearbyInteractionManager.isSupported
    @Published private(set) var known: [KnownPerson] = []
    @Published private(set) var chats: [String: [ChatMessage]] = [:]
    @Published private(set) var unread: [String: Int] = [:]
    @Published private(set) var locationAuthDescription = "not determined"
    private var seenChatIds: Set<String> = []
    private var activeChatName: String?
    private var chatTimer: Timer?
    var totalUnread: Int { unread.values.reduce(0, +) }
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
        let name: String
        if let stored = UserDefaults.standard.string(forKey: Self.nameKey) {
            name = stored
        } else {
            name = NameGenerator.random()
            UserDefaults.standard.set(name, forKey: Self.nameKey) // stable across launches
        }
        displayName = name
        findableMode = UserDefaults.standard.bool(forKey: Self.findableKey)
        if let data = UserDefaults.standard.data(forKey: Self.knownKey),
           let list = try? JSONDecoder().decode([KnownPerson].self, from: data) {
            known = list
        }
        if let data = UserDefaults.standard.data(forKey: Self.chatsKey),
           let stored = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) {
            chats = stored
        }
        if let ids = UserDefaults.standard.stringArray(forKey: Self.seenChatKey) {
            seenChatIds = Set(ids)
        }
        mpc = MultipeerService(displayName: name)
        super.init()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Log.add("app", "=== Locompass \(version) launched, I am \"\(name)\", findable=\(findableMode) ===")
        observeLifecycle()
        mpc.delegate = self
        ni.delegate = self
        scanner.delegate = self
        scanner.myName = name
        beacon.onChat = { [weak self] env in self?.handleEnvelope(env) }
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
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.refreshConnectivity()
        }
    }

    /// MPC browsers/advertisers go stale after time in the background —
    /// restart discovery and drop unconnected entries so nobody sits on
    /// "connecting…" forever after re-entering the app.
    private func refreshConnectivity() {
        guard started else { return }
        Log.add("app", "foreground refresh: restarting discovery, pruning stale peers")
        peers.removeAll { $0.kind == .mpc && !$0.connected }
        mpc.restartDiscovery()
        scanner.start()
    }

    func start() {
        guard !started else { return }
        started = true
        mpc.start()
        location.start()
        scanner.start()
        updateBeacon()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Log.add("app", "notifications \(ok ? "granted" : "denied")")
        }
        chatTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.retryOutbox()
        }
    }

    // MARK: identity
    func setDisplayName(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != displayName else { return }
        Log.add("app", "display name → \(name)")
        displayName = name
        scanner.myName = name
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

    /// Stable ordering for lists: live friends first (alphabetical — their
    /// seenAt updates every second and would shuffle), then stale ones by
    /// frozen last-seen time.
    var knownSorted: [KnownPerson] {
        known.sorted { a, b in
            let aLive = isLive(a.name), bLive = isLive(b.name)
            if aLive != bLive { return aLive }
            if aLive { return a.name < b.name }
            return a.seenAt > b.seenAt
        }
    }

    func forget(names: [String]) {
        known.removeAll { names.contains($0.name) }
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
        persistKnown()
    }
    private func persistKnown(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastKnownSave) > 5 else { return }
        lastKnownSave = Date()
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: Self.knownKey)
        }
    }

    // MARK: people (merged transports)
    var people: [Person] {
        var byName: [String: Person] = [:]
        var order: [String] = []
        for p in peers {
            if byName[p.name] == nil {
                byName[p.name] = Person(name: p.name)
                order.append(p.name)
            }
            if p.kind == .mpc { byName[p.name]?.mpc = p } else { byName[p.name]?.ble = p }
        }
        return order.compactMap { byName[$0] }.sorted { l, r in
            if l.connected != r.connected { return l.connected }
            return l.name < r.name
        }
    }

    /// Best available navigation data for a person: fresh UWB wins, then GPS
    /// (over either transport), with a label saying what's in use.
    func nav(for name: String) -> PersonNav {
        let mpcPeer = peers.first { $0.name == name && $0.kind == .mpc && $0.connected }
        let blePeer = peers.first { $0.name == name && $0.kind == .ble && $0.connected }
        let uwbFresh = mpcPeer?.lastUWB.map { Date().timeIntervalSince($0) < 3 } ?? false

        var absBearing: Double?
        var gpsDistance: Float?
        if let k = known.first(where: { $0.name == name }), let lat = k.lat, let lon = k.lon,
           let me = myCoord {
            let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            absBearing = Geo.bearing(from: me, to: c)
            gpsDistance = Float(Geo.distance(from: me, to: c))
        }

        if uwbFresh, let mp = mpcPeer {
            if let dir = mp.uwbDirection {
                return PersonNav(distance: mp.distance, angle: Geo.azimuthDegrees(dir),
                                 source: .uwb, usingLabel: "Precise (UWB)", rssi: blePeer?.rssi)
            }
            if let b = absBearing {
                return PersonNav(distance: mp.distance, angle: b - myHeading,
                                 source: .uwb, usingLabel: "UWB distance · GPS arrow", rssi: blePeer?.rssi)
            }
            return PersonNav(distance: mp.distance, angle: nil,
                             source: .uwb, usingLabel: "UWB distance — sweep for direction", rssi: blePeer?.rssi)
        }
        if let b = absBearing {
            let label: String
            if mpcPeer == nil && blePeer == nil {
                // Offline: navigate to where they last were.
                if let seen = known.first(where: { $0.name == name })?.seenAt {
                    let rel = RelativeDateTimeFormatter().localizedString(for: seen, relativeTo: Date())
                    label = "Not connected · last seen \(rel)"
                } else {
                    label = "Not connected · last known position"
                }
            } else if mpcPeer == nil && blePeer != nil {
                label = "GPS · via Bluetooth beacon"
            } else {
                label = "GPS (approximate)"
            }
            return PersonNav(distance: gpsDistance, angle: b - myHeading,
                             source: .gps, usingLabel: label, rssi: blePeer?.rssi)
        }
        return PersonNav(distance: nil, angle: nil, source: .none,
                         usingLabel: "Acquiring…", rssi: blePeer?.rssi)
    }

    // MARK: chat
    func sendChat(_ text: String, to name: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let env = ChatEnvelope(kind: .chat, id: UUID().uuidString, from: displayName,
                               to: name, text: String(clean.prefix(300)), ts: Date())
        chats[name, default: []].append(
            ChatMessage(id: env.id, text: env.text ?? "", ts: env.ts, outgoing: true, acked: false))
        persistChats()
        Log.add("chat", "queued message to \(name)")
        deliver(env)
    }

    func openChat(_ name: String) {
        activeChatName = name
        unread[name] = 0
    }
    func closeChat(_ name: String) {
        if activeChatName == name { activeChatName = nil }
    }

    /// Push an envelope over every live transport; the retry timer re-sends
    /// unacked messages until an ack comes back.
    private func deliver(_ env: ChatEnvelope) {
        var sent: [String] = []
        if let mp = peers.first(where: { $0.name == env.to && $0.kind == .mpc && $0.connected }),
           let peerID = peerIDs[mp.id] {
            mpc.send(PeerMessage(kind: .chat, chat: env), to: peerID)
            sent.append("mpc")
        }
        if scanner.sendChat(env, toPersonNamed: env.to) { sent.append("ble-write") }
        if findableMode {
            beacon.enqueueChat(env) // recipient may reach us as a central
            sent.append("beacon-queue")
        }
        if env.kind == .chat {
            Log.add("chat", "deliver \(env.id.prefix(6)) to \(env.to) via [\(sent.joined(separator: ","))]")
        }
    }

    private func retryOutbox() {
        for (name, msgs) in chats {
            for m in msgs where m.outgoing && !m.acked && Date().timeIntervalSince(m.ts) < 48 * 3600 {
                deliver(ChatEnvelope(kind: .chat, id: m.id, from: displayName,
                                     to: name, text: m.text, ts: m.ts))
            }
        }
    }

    private func handleEnvelope(_ env: ChatEnvelope) {
        switch env.kind {
        case .chat:
            let ack = ChatEnvelope(kind: .ack, id: env.id, from: displayName,
                                   to: env.from, text: nil, ts: Date())
            guard !seenChatIds.contains(env.id) else {
                deliver(ack) // duplicate — re-ack, sender may have missed it
                return
            }
            seenChatIds.insert(env.id)
            persistSeenChatIds()
            chats[env.from, default: []].append(
                ChatMessage(id: env.id, text: env.text ?? "", ts: env.ts, outgoing: false, acked: true))
            if activeChatName != env.from { unread[env.from, default: 0] += 1 }
            persistChats()
            remember(name: env.from)
            deliver(ack)
            notifyIncoming(env)
            Log.add("chat", "message from \(env.from)")
        case .ack:
            if var msgs = chats[env.from], let i = msgs.firstIndex(where: { $0.id == env.id && !$0.acked }) {
                msgs[i].acked = true
                chats[env.from] = msgs
                persistChats()
                Log.add("chat", "ack from \(env.from) for \(env.id.prefix(6))")
            }
            beacon.removePendingChat(id: env.id)
        }
    }

    private func notifyIncoming(_ env: ChatEnvelope) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = env.from
        content.body = env.text ?? ""
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: env.id, content: content, trigger: nil))
    }

    private func persistChats() {
        for (name, msgs) in chats where msgs.count > 500 {
            chats[name] = Array(msgs.suffix(500))
        }
        if let data = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(data, forKey: Self.chatsKey)
        }
    }
    private func persistSeenChatIds() {
        if seenChatIds.count > 1000 { seenChatIds = Set(Array(seenChatIds).suffix(500)) }
        UserDefaults.standard.set(Array(seenChatIds), forKey: Self.seenChatKey)
    }

    // MARK: navigation
    func startNavigating(toPerson name: String) {
        Log.add("app", "navigating to \(name)")
        activePersonName = name
        startUWBIfPossible(for: name)
    }
    private func startUWBIfPossible(for name: String) {
        guard let mp = peers.first(where: { $0.name == name && $0.kind == .mpc && $0.connected })
        else { return }
        if uwbSupported { ni.start(peerKey: mp.id) } // emits our token via delegate
        sendLocation(to: mp.id)
    }
    func stopNavigating() {
        if let name = activePersonName {
            for p in peers where p.name == name && p.kind == .mpc { ni.stop(peerKey: p.id) }
        }
        activePersonName = nil
    }

    // MARK: GPS
    private func handleMyLocation(_ c: CLLocationCoordinate2D) {
        myCoord = c
        if let name = activePersonName,
           let mp = peers.first(where: { $0.name == name && $0.kind == .mpc && $0.connected }) {
            sendLocation(to: mp.id)
        }
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
            // GPS only owns the readout when UWB ranging is stale — UWB often
            // has distance but no direction, and must not be overwritten then.
            let uwbFresh = peers[i].lastUWB.map { Date().timeIntervalSince($0) < 3 } ?? false
            if !uwbFresh {
                peers[i].distance = Float(Geo.distance(from: me, to: p))
                peers[i].source = .gps
            }
        }
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
            // If we're already on this person's compass screen, kick off UWB now.
            if pretty(peerID.displayName) == activePersonName {
                startUWBIfPossible(for: pretty(peerID.displayName))
            }
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
        case .chat:
            if let env = message.chat { handleEnvelope(env) }
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
        if let d {
            peers[i].distance = d
            peers[i].source = .uwb
            peers[i].lastUWB = Date()
        }
        if d == nil && direction == nil { // UWB lost the peer — GPS may take over
            peers[i].lastUWB = nil
            peers[i].source = peers[i].absBearing != nil ? .gps : .none
        }
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
    func scanner(_ s: FindableScanner, didReceiveChat env: ChatEnvelope) {
        handleEnvelope(env)
    }
}
