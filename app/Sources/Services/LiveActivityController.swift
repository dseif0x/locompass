import Foundation
import ActivityKit

/// Starts/updates/ends the navigation Live Activity while a compass screen
/// is open. Updates are throttled to ~1/s.
@MainActor
final class LiveActivityController {
    private var lastUpdate = Date.distantPast

    func start(friend: String) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.add("live", "Live Activities disabled in system settings")
            return
        }
        end()
        let attrs = NavActivityAttributes(friendName: friend)
        let state = NavActivityAttributes.ContentState(angle: nil, distanceText: "…", sourceText: "Acquiring…")
        do {
            _ = try Activity.request(attributes: attrs, contentState: state)
            Log.add("live", "activity started for \(friend)")
        } catch {
            Log.add("live", "activity start failed: \(error.localizedDescription)")
        }
    }

    func update(angle: Double?, distanceText: String, sourceText: String) {
        guard #available(iOS 16.1, *) else { return }
        guard Date().timeIntervalSince(lastUpdate) > 1 else { return }
        lastUpdate = Date()
        let state = NavActivityAttributes.ContentState(angle: angle, distanceText: distanceText, sourceText: sourceText)
        Task {
            for activity in Activity<NavActivityAttributes>.activities {
                await activity.update(using: state)
            }
        }
    }

    func end() {
        guard #available(iOS 16.1, *) else { return }
        Task {
            for activity in Activity<NavActivityAttributes>.activities {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }
}
