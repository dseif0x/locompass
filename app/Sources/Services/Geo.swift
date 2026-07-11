import CoreLocation
import simd

enum Geo {
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi/180, lat2 = b.latitude * .pi/180
        let dLon = (b.longitude - a.longitude) * .pi/180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1)*sin(lat2) - sin(lat1)*cos(lat2)*cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    /// Simplified device-local azimuth (degrees) from a UWB direction vector — matches
    /// Apple's NIPeekaboo sample. For production, enable camera assistance and study that
    /// sample for full device-orientation handling.
    static func azimuthDegrees(_ dir: simd_float3) -> Double {
        Double(asin(max(-1, min(1, dir.x)))) * 180 / .pi
    }
}
