import SwiftUI
import MapKit

/// Wrapped MKMapView: SwiftUI's Map on iOS 16 can't switch map types, this
/// can. Shows friend pins with name + time callouts, diffs annotations in
/// place (no flicker on live updates), and re-fits when fitTrigger changes.
struct FriendMapPin {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let live: Bool
    let subtitle: String
}

struct MapKitView: UIViewRepresentable {
    var pins: [FriendMapPin]
    var mapTypeRaw: Int
    @Binding var fitTrigger: Int

    static let mapTypes: [MKMapType] = [.standard, .satellite, .hybrid]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.mapType = Self.mapTypes[min(max(mapTypeRaw, 0), Self.mapTypes.count - 1)]
        context.coordinator.sync(pins: pins, on: map)
        if context.coordinator.lastFit != fitTrigger {
            context.coordinator.lastFit = fitTrigger
            context.coordinator.fitAll(on: map)
        }
    }

    final class FriendAnnotation: MKPointAnnotation {
        var live = false
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastFit = -1 // differs from the initial trigger → fits on first update
        private var annotations: [String: FriendAnnotation] = [:]

        func sync(pins: [FriendMapPin], on map: MKMapView) {
            var seen = Set<String>()
            for pin in pins {
                seen.insert(pin.name)
                if let a = annotations[pin.name] {
                    a.coordinate = pin.coordinate
                    a.subtitle = pin.subtitle
                    if a.live != pin.live {
                        a.live = pin.live
                        if let v = map.view(for: a) as? MKMarkerAnnotationView {
                            v.markerTintColor = pin.live ? .systemGreen : .systemBlue
                        }
                    }
                } else {
                    let a = FriendAnnotation()
                    a.title = pin.name
                    a.subtitle = pin.subtitle
                    a.coordinate = pin.coordinate
                    a.live = pin.live
                    annotations[pin.name] = a
                    map.addAnnotation(a)
                }
            }
            for (name, a) in annotations where !seen.contains(name) {
                map.removeAnnotation(a)
                annotations[name] = nil
            }
        }

        func fitAll(on map: MKMapView) {
            let anns = map.annotations
            guard !anns.isEmpty else { return }
            map.showAnnotations(anns, animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let fa = annotation as? FriendAnnotation else { return nil } // default blue dot for user
            let id = "friend"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: fa, reuseIdentifier: id)
            view.annotation = fa
            view.canShowCallout = true
            view.markerTintColor = fa.live ? .systemGreen : .systemBlue
            view.titleVisibility = .visible
            view.subtitleVisibility = .visible
            return view
        }
    }
}

/// Segmented map-type control shared by both map screens.
struct MapTypePicker: View {
    @Binding var raw: Int
    var body: some View {
        Picker("Map type", selection: $raw) {
            Text("Map").tag(0)
            Text("Satellite").tag(1)
            Text("Hybrid").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 32)
    }
}
