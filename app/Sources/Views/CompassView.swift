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
                            Text("Sweep your phone…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let d = peer.distance {
                    Text(String(format: "%.1f m", d))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                }

                Label(label(peer.source),
                      systemImage: peer.source == .uwb ? "dot.radiowaves.left.and.right" : "location")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.startNavigating(to: peerID) }
        .onDisappear { vm.stopNavigating() }
    }

    private func label(_ s: NavSource) -> String {
        switch s {
        case .uwb:  return "Precise (UWB)"
        case .gps:  return "Approximate (GPS)"
        case .none: return "Acquiring…"
        }
    }
}
