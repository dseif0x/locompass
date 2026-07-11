import Foundation
import simd

enum NavSource { case none, gps, uwb }

struct Peer: Identifiable, Equatable {
    let id: String            // MCPeerID.displayName (unique per launch)
    var name: String          // pretty label (portion before '#')
    var connected: Bool = false

    var distance: Float?       // meters (UWB or GPS)
    var uwbDirection: simd_float3?
    var absBearing: Double?    // 0..360 true-north bearing (GPS)
    var lastLat: Double?
    var lastLon: Double?
    var source: NavSource = .none

    static func == (a: Peer, b: Peer) -> Bool { a.id == b.id }
}
