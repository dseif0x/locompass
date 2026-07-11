import SwiftUI
import MapKit
import CoreLocation

/// Shows a person's last received GPS position (live "Now" for connected
/// peers, persisted last-seen otherwise) on an Apple Maps view. Without
/// internet the tiles may be blank, but the marker, distance, and
/// coordinates still work.
struct PersonMapView: View {
    let name: String
    @EnvironmentObject var vm: CompassViewModel
    @AppStorage("mapTypeRaw") private var mapTypeRaw = 0
    @State private var fitTrigger = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            content
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        if let info = vm.lastLocation(for: name) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    MapKitView(
                        pins: [FriendMapPin(name: name, coordinate: info.coordinate,
                                            live: info.live, subtitle: timeText(info))],
                        mapTypeRaw: mapTypeRaw,
                        fitTrigger: $fitTrigger)
                    MapTypePicker(raw: $mapTypeRaw)
                        .padding(.top, 8)
                }

                VStack(spacing: 6) {
                    Label(timeText(info), systemImage: info.live ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.subheadline)
                    if let me = vm.myCoordinate {
                        Text(String(format: "%.0f m from you", Geo.distance(from: me, to: info.coordinate)))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Center on \(name)") { fitTrigger += 1 }
                        .font(.footnote)
                    Text("No internet? The map may be blank — the marker and distance still work.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(10)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash").font(.largeTitle)
                Text("No location received from \(name) yet.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func timeText(_ info: PeerLocationInfo) -> String {
        if info.live { return "Now" }
        guard let t = info.seenAt else { return "Last seen: unknown" }
        return "Last seen " + RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date())
    }
}
