import Foundation
import simd

enum NavSource { case none, gps, uwb }

enum PeerKind { case mpc, ble }

struct Peer: Identifiable, Equatable {
    let id: String            // MCPeerID.displayName, or "ble:<peripheral UUID>"
    var name: String          // pretty label (portion before '#')
    var kind: PeerKind = .mpc
    var connected: Bool = false
    var rssi: Int?             // BLE signal strength (findable peers)

    var distance: Float?       // meters (UWB or GPS)
    var uwbDirection: simd_float3?
    var lastUWB: Date?         // last time UWB delivered a distance
    var absBearing: Double?    // 0..360 true-north bearing (GPS)
    var lastLat: Double?
    var lastLon: Double?
    var source: NavSource = .none

    static func == (a: Peer, b: Peer) -> Bool { a.id == b.id }
}
