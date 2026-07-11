import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: CompassViewModel
    var body: some View {
        NavigationStack {
            PeerListView().navigationTitle("Nearby")
        }
        .onAppear { vm.start() }
    }
}
