import SwiftUI
import MapKit
import CoreLocation

/// One map with everyone's last known position from the past 24 hours.
/// Green pin + "Now" for currently connected friends, blue pin + relative
/// time for stale ones. Tiles need internet; pins and distances don't.
struct FriendsMapView: View {
    @EnvironmentObject var vm: CompassViewModel
    @AppStorage("mapTypeRaw") private var mapTypeRaw = 0
    @State private var fitTrigger = 0

    private var pins: [FriendMapPin] {
        vm.known.compactMap { k in
            guard let lat = k.lat, let lon = k.lon,
                  Date().timeIntervalSince(k.seenAt) < 24 * 3600 else { return nil }
            let live = vm.isLive(k.name)
            return FriendMapPin(name: k.name,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                live: live,
                                subtitle: live ? "Now" : relative(k.seenAt))
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            ZStack {
                MapKitView(pins: pins, mapTypeRaw: mapTypeRaw, fitTrigger: $fitTrigger)

                VStack(spacing: 8) {
                    MapTypePicker(raw: $mapTypeRaw)
                        .padding(.top, 8)
                    Spacer()
                    if pins.isEmpty {
                        Text("No friend locations in the last 24 h yet.")
                            .font(.footnote)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        fitTrigger += 1
                    } label: {
                        Label("Fit all", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
