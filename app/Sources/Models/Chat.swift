import Foundation

enum ChatEnvelopeKind: String, Codable { case chat, ack }

/// Wire format for messages and acks, identical over MultipeerConnectivity
/// and the BLE beacon characteristics.
struct ChatEnvelope: Codable, Identifiable {
    var kind: ChatEnvelopeKind
    var id: String       // message UUID — dedupe + ack key
    var from: String
    var to: String
    var text: String?
    var ts: Date
}

/// A message as stored locally (per conversation partner).
struct ChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let ts: Date
    let outgoing: Bool
    var acked: Bool
}
