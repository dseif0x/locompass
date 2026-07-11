import Foundation

struct PeerMessage: Codable {
    enum Kind: String, Codable { case token, location }
    var kind: Kind
    var tokenB64: String?   // for .token
    var lat: Double?        // for .location
    var lon: Double?
}
