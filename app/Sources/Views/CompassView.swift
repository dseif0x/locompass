import SwiftUI

struct CompassView: View {
    let peerID: String
    @EnvironmentObject var vm: CompassViewModel

    private var peer: Peer? { vm.peers.first { $0.id == peerID } }

    var body: some View {
        VStack(spacing: 32) {
            if let peer {
                Text(peer.name).font(.title2).bold()

                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2).frame(width: 260, height: 260)
                    if let angle = vm.arrowAngle(for: peer) {
                        Image(systemName: "location.north.fill")
                            .resizable().scaledToFit().frame(width: 120, height: 120)
                            .rotationEffect(.degrees(angle))
                            .animation(.easeOut(duration: 0.2), value: angle)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 44))
                            Text("Acquiring signal…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let d = peer.distance {
                    Text(String(format: "%.0f m", d))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                }

                Label(label(peer.source),
                      systemImage: peer.source == .uwb ? "dot.radiowaves.left.and.right" : "location")
                    .font(.footnote).foregroundStyle(.secondary)

                if peer.kind == .ble, let rssi = peer.rssi {
                    let b = bars(rssi)
                    Label("Signal \(String(repeating: "●", count: b))\(String(repeating: "○", count: 5 - b))",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    PersonMapView(name: peer?.name ?? "")
                } label: {
                    Image(systemName: "map")
                }
            }
        }
        .onAppear {
            vm.startNavigating(to: peerID)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            vm.stopNavigating()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func label(_ s: NavSource) -> String {
        switch s {
        case .uwb:
            // Distance is UWB-precise; the arrow may still be GPS if the peer
            // is outside the UWB antenna's field of view.
            return peer?.uwbDirection != nil ? "Precise (UWB)" : "Precise distance (UWB) · GPS arrow"
        case .gps:  return "Approximate (GPS)"
        case .none: return "Acquiring…"
        }
    }

    /// Rough BLE signal → 1–5 bars, useful as hot/cold for the last meters.
    private func bars(_ rssi: Int) -> Int {
        switch rssi {
        case (-50)...: return 5
        case (-60)...: return 4
        case (-70)...: return 3
        case (-80)...: return 2
        default:       return 1
        }
    }
}
