import SwiftUI

struct CompassView: View {
    let name: String
    @EnvironmentObject var vm: CompassViewModel

    var body: some View {
        let nav = vm.nav(for: name)
        VStack(spacing: 32) {
            Text(name).font(.title2).bold()

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2).frame(width: 260, height: 260)
                if let angle = nav.angle {
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

            if let d = nav.distance {
                Text(String(format: "%.0f m", d))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
            }

            Label(nav.usingLabel,
                  systemImage: nav.source == .uwb ? "dot.radiowaves.left.and.right" : "location")
                .font(.footnote).foregroundStyle(.secondary)

            if let rssi = nav.rssi {
                let b = bars(rssi)
                Label("Signal \(String(repeating: "●", count: b))\(String(repeating: "○", count: 5 - b))",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    PersonMapView(name: name)
                } label: {
                    Image(systemName: "map")
                }
            }
        }
        .onAppear {
            vm.startNavigating(toPerson: name)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            vm.stopNavigating()
            UIApplication.shared.isIdleTimerDisabled = false
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
