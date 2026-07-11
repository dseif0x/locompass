import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: CompassViewModel
    var body: some View {
        TabView {
            NavigationStack {
                PeerListView().navigationTitle("Nearby")
            }
            .tabItem { Label("Friends", systemImage: "person.2") }

            NavigationStack {
                FriendsMapView().navigationTitle("Map")
            }
            .tabItem { Label("Map", systemImage: "map") }

            NavigationStack {
                ChatsListView()
            }
            .tabItem { Label("Messages", systemImage: "message") }
            .badge(vm.totalUnread)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear { vm.start() }
    }
}
