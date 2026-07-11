import SwiftUI
import MapKit
import CoreLocation

/// One map with everyone's last known position from the past 24 hours.
/// Green pin + "Now" for currently connected friends, blue pin + relative
/// time for stale ones. Tiles need internet; pins and distances don't.
struct FriendsMapView: View {
    @EnvironmentObject var vm: CompassViewModel

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        latitudinalMeters: 1000, longitudinalMeters: 1000)
    @State private var didFit = false

    private struct Pin: Identifiable {
        let id: String
        let coord: CLLocationCoordinate2D
        let live: Bool
        let seenAt: Date
    }

    private var pins: [Pin] {
        vm.known.compactMap { k in
            guard let lat = k.lat, let lon = k.lon,
                  Date().timeIntervalSince(k.seenAt) < 24 * 3600 else { return nil }
            return Pin(id: k.name,
                       coord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                       live: vm.isLive(k.name),
                       seenAt: k.seenAt)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            ZStack(alignment: .bottom) {
                Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: pins) { pin in
                    MapAnnotation(coordinate: pin.coord) {
                        VStack(spacing: 2) {
                            Text(pin.id)
                                .font(.caption2).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(pin.live ? Color.green : Color.blue)
                            Text(timeText(pin))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }

                VStack(spacing: 8) {
                    if pins.isEmpty {
                        Text("No friend locations in the last 24 h yet.")
                            .font(.footnote)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        fit()
                    } label: {
                        Label("Fit all", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            if !didFit {
                didFit = true
                fit()
            }
        }
    }

    private func timeText(_ pin: Pin) -> String {
        if pin.live { return "Now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: pin.seenAt, relativeTo: Date())
    }

    private func fit() {
        var coords = pins.map(\.coord)
        if let me = vm.myCoordinate { coords.append(me) }
        guard !coords.isEmpty else { return }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
                                   longitudeDelta: max((maxLon - minLon) * 1.4, 0.003)))
    }
}
