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

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        latitudinalMeters: 600, longitudinalMeters: 600)
    @State private var didCenter = false

    private struct Pin: Identifiable {
        let id = "pin"
        let coord: CLLocationCoordinate2D
    }

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
                Map(coordinateRegion: $region, showsUserLocation: true,
                    annotationItems: [Pin(coord: info.coordinate)]) { pin in
                    MapMarker(coordinate: pin.coord, tint: .blue)
                }
                .onAppear {
                    if !didCenter {
                        didCenter = true
                        center(on: info.coordinate)
                    }
                }

                VStack(spacing: 6) {
                    Label(timeText(info), systemImage: info.live ? "dot.radiowaves.left.and.right" : "clock")
                        .font(.subheadline)
                    if let me = vm.myCoordinate {
                        Text(String(format: "%.0f m from you", Geo.distance(from: me, to: info.coordinate)))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Center on \(name)") { center(on: info.coordinate) }
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

    private func center(on c: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600)
    }

    private func timeText(_ info: PeerLocationInfo) -> String {
        if info.live { return "Now" }
        guard let t = info.seenAt else { return "Last seen: unknown" }
        return "Last seen " + RelativeDateTimeFormatter().localizedString(for: t, relativeTo: Date())
    }
}
