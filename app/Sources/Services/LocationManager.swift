import Foundation
import CoreLocation

final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onHeading: ((Double) -> Void)? // degrees, true north
    var onAuth: ((CLAuthorizationStatus) -> Void)?

    private var lastFixLog = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    /// Upgrade prompt from "While Using" to "Always" — makes background
    /// operation (findable mode) far more robust against iOS suspending us.
    func requestAlways() {
        Log.add("loc", "requesting Always authorization (current: \(Self.describe(manager.authorizationStatus)))")
        manager.requestAlwaysAuthorization()
    }

    /// Keep GPS updates flowing while the app is backgrounded / the phone is
    /// locked (findable mode). Requires the "location" background mode.
    func setBackgroundUpdates(_ enabled: Bool) {
        Log.add("loc", "background updates \(enabled ? "on" : "off")")
        manager.allowsBackgroundLocationUpdates = enabled
        manager.pausesLocationUpdatesAutomatically = !enabled
        manager.showsBackgroundLocationIndicator = true
        // Significant-change monitoring relaunches the app when the device
        // moves a few hundred meters — even after the user swiped it away.
        if enabled {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    static func describe(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined:       return "not determined"
        case .restricted:          return "restricted"
        case .denied:              return "denied"
        case .authorizedAlways:    return "Always"
        case .authorizedWhenInUse: return "While Using"
        @unknown default:          return "unknown"
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Log.add("loc", "authorization: \(Self.describe(m.authorizationStatus))")
        onAuth?(m.authorizationStatus)
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        if Date().timeIntervalSince(lastFixLog) > 15 {
            lastFixLog = Date()
            Log.add("loc", String(format: "fix ±%.0fm", l.horizontalAccuracy))
        }
        onLocation?(l.coordinate)
    }
    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        if h.trueHeading >= 0 { onHeading?(h.trueHeading) }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Log.add("loc", "error: \(error.localizedDescription)")
    }
}
