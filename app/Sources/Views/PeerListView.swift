import SwiftUI

struct PeerListView: View {
    @EnvironmentObject var vm: CompassViewModel
    @State private var nameDraft = ""

    private var mpcPeers: [Peer] { vm.peers.filter { $0.kind == .mpc } }
    private var blePeers: [Peer] { vm.peers.filter { $0.kind == .ble } }

    var body: some View {
        List {
            Section("You") {
                TextField("Your name", text: $nameDraft)
                    .submitLabel(.done)
                    .onSubmit { vm.setDisplayName(nameDraft) }
                Toggle("Findable while locked", isOn: $vm.findableMode)
                if vm.findableMode {
                    Text("Friends can find you while this phone is locked — as long as Locompass stays open in the background. Don't swipe it away.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !vm.uwbSupported {
                Section {
                    Label("This device has no UWB — GPS arrow only.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Nearby (precise)") {
                ForEach(mpcPeers) { peer in
                    if peer.connected {
                        NavigationLink { CompassView(peerID: peer.id) } label: { row(peer) }
                    } else {
                        row(peer).foregroundStyle(.secondary)
                    }
                }
                if mpcPeers.isEmpty {
                    Text("Looking for friends nearby… both phones need the app open in the foreground.")
                        .foregroundStyle(.secondary)
                }
            }

            if !blePeers.isEmpty {
                Section("Findable friends (their phone can be locked)") {
                    ForEach(blePeers) { peer in
                        if peer.connected {
                            NavigationLink { CompassView(peerID: peer.id) } label: { row(peer) }
                        } else {
                            row(peer).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { nameDraft = vm.displayName }
    }

    private func row(_ peer: Peer) -> some View {
        HStack {
            Circle().fill(peer.connected ? .green : .gray).frame(width: 8, height: 8)
            Text(peer.name)
            Spacer()
            if !peer.connected {
                Text("connecting…").font(.footnote).foregroundStyle(.secondary)
            } else if let d = peer.distance {
                Text(String(format: "%.0f m", d)).foregroundStyle(.secondary)
            }
        }
    }
}
