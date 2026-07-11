import Foundation
import ActivityKit

/// Shared between the app and the widget extension: the Live Activity that
/// mirrors the compass to the lock screen, Dynamic Island, and the Apple
/// Watch Smart Stack (watchOS 10+ mirrors iPhone Live Activities — no watch
/// app install needed).
@available(iOS 16.1, *)
struct NavActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var angle: Double?        // arrow rotation in degrees; nil = acquiring
        var distanceText: String
        var sourceText: String
    }
    var friendName: String
}
