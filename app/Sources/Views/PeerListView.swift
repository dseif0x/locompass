import SwiftUI

struct PeerListView: View {
    @EnvironmentObject var vm: CompassViewModel

    var body: some View {
        List {
            if !vm.uwbSupported {
                Section {
                    Label("This device has no UWB — GPS arrow only.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Nearby devices") {
                ForEach(vm.peers) { peer in
                    if peer.connected {
                        NavigationLink { CompassView(peerID: peer.id) } label: { row(peer) }
                    } else {
                        row(peer).foregroundStyle(.secondary)
                    }
                }
                if vm.peers.isEmpty {
                    Text("Looking for friends nearby… make sure both phones have the app open.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ peer: Peer) -> some View {
        HStack {
            Circle().fill(peer.connected ? .green : .gray).frame(width: 8, height: 8)
            Text(peer.name)
            Spacer()
            if !peer.connected {
                Text("connecting…").font(.footnote).foregroundStyle(.secondary)
            } else if let d = peer.distance {
                Text(String(format: "%.1f m", d)).foregroundStyle(.secondary)
            }
        }
    }
}
