import Foundation

/// A friend we've connected to at least once — survives relaunches so their
/// last received GPS position can be shown on a map even when they're gone.
struct KnownPerson: Codable, Identifiable, Equatable {
    var name: String
    var lat: Double?
    var lon: Double?
    var seenAt: Date
    var id: String { name }
}
