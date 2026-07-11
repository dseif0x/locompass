import Foundation

/// One human, merged across transports: the same friend may be reachable via
/// MultipeerConnectivity (UWB-capable) and via the BLE findable beacon.
struct Person: Identifiable {
    let name: String
    var mpc: Peer?
    var ble: Peer?
    var id: String { name }
    var connected: Bool { (mpc?.connected ?? false) || (ble?.connected ?? false) }
}

/// The best navigation data currently available for a person.
struct PersonNav {
    var distance: Float?
    var angle: Double?
    var source: NavSource
    var usingLabel: String
    var rssi: Int?
}
