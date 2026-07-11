import SwiftUI
import UIKit

/// Handles background relaunches: iOS restarts us (without any UI) for
/// significant location changes — even after the user swiped the app away —
/// and for Bluetooth state restoration after a system kill. In both cases
/// services must be started here, because no view ever appears.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let bgKeys: [UIApplication.LaunchOptionsKey] = [.location, .bluetoothPeripherals, .bluetoothCentrals]
        if let launchOptions, bgKeys.contains(where: { launchOptions[$0] != nil }) {
            Log.add("app", "relaunched in BACKGROUND by iOS — restarting services")
            CompassViewModel.shared.start()
        }
        return true
    }
}

@main
struct CompassFriendsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vm = CompassViewModel.shared
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(vm)
        }
    }
}
