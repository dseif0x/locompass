import Foundation

struct PeerMessage: Codable {
    enum Kind: String, Codable { case token, location, chat }
    var kind: Kind
    var tokenB64: String?      // for .token
    var lat: Double?           // for .location
    var lon: Double?
    var chat: ChatEnvelope?    // for .chat (message or ack)
}
