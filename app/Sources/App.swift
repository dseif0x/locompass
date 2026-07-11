import SwiftUI

@main
struct CompassFriendsApp: App {
    @StateObject private var vm = CompassViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(vm)
        }
    }
}
