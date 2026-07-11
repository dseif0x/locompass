import Foundation
import CoreBluetooth

/// Advertises this phone over BLE and serves its GPS position via GATT so a
/// friend can find us while this phone is locked. Requires the
/// bluetooth-peripheral + location background modes; the app must stay
/// running (backgrounded is fine, force-quit is not).
final class FindableBeacon: NSObject {
    static let serviceUUID  = CBUUID(string: "F3641400-3E4C-4E12-9D6B-6C0A2C6E1A01")
    static let nameCharUUID = CBUUID(string: "F3641401-3E4C-4E12-9D6B-6C0A2C6E1A01")
    static let locCharUUID  = CBUUID(string: "F3641402-3E4C-4E12-9D6B-6C0A2C6E1A01")

    private var manager: CBPeripheralManager?
    private var locChar: CBMutableCharacteristic?
    private var displayName = ""
    private var payload = Data()
    private var active = false

    func start(displayName: String) {
        Log.add("beacon", "start as \(displayName)")
        self.displayName = displayName
        active = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            setup()
        }
    }

    func stop() {
        Log.add("beacon", "stop")
        active = false
        manager?.stopAdvertising()
        manager?.removeAllServices()
    }

    func update(lat: Double, lon: Double) {
        payload = (try? JSONEncoder().encode(BeaconLocation(lat: lat, lon: lon))) ?? Data()
        if let c = locChar {
            manager?.updateValue(payload, for: c, onSubscribedCentrals: nil)
        }
    }

    private func setup() {
        guard active, let manager, manager.state == .poweredOn else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        let name = CBMutableCharacteristic(type: Self.nameCharUUID, properties: .read,
                                           value: Data(displayName.utf8), permissions: .readable)
        let loc = CBMutableCharacteristic(type: Self.locCharUUID, properties: [.read, .notify],
                                          value: nil, permissions: .readable)
        locChar = loc
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [name, loc]
        manager.add(service)
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: displayName, // dropped by iOS while backgrounded
        ])
    }
}

struct BeaconLocation: Codable {
    var lat: Double
    var lon: Double
}

extension FindableBeacon: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Log.add("beacon", "bluetooth state: \(peripheral.state.rawValue) (\(peripheral.state == .poweredOn ? "on" : "not ready"))")
        if peripheral.state == .poweredOn { setup() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { Log.add("beacon", "add service failed: \(error.localizedDescription)") }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Log.add("beacon", error.map { "advertising failed: \($0.localizedDescription)" } ?? "advertising")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        Log.add("beacon", "a seeker subscribed to our position")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        Log.add("beacon", "a seeker unsubscribed")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.locCharUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        guard request.offset <= payload.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = payload.subdata(in: request.offset..<payload.count)
        peripheral.respond(to: request, withResult: .success)
    }
}
