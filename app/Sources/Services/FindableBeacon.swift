import Foundation
import CoreBluetooth

/// Advertises this phone over BLE and serves its GPS position + chat traffic
/// via GATT so a friend can find and message us while this phone is locked.
/// Requires the bluetooth-peripheral + location background modes; the app
/// must stay running (backgrounded is fine, force-quit is not).
final class FindableBeacon: NSObject {
    static let serviceUUID  = CBUUID(string: "F3641400-3E4C-4E12-9D6B-6C0A2C6E1A01")
    static let nameCharUUID = CBUUID(string: "F3641401-3E4C-4E12-9D6B-6C0A2C6E1A01")
    static let locCharUUID  = CBUUID(string: "F3641402-3E4C-4E12-9D6B-6C0A2C6E1A01")
    static let chatInCharUUID  = CBUUID(string: "F3641403-3E4C-4E12-9D6B-6C0A2C6E1A01") // centrals write envelopes to us
    static let chatOutCharUUID = CBUUID(string: "F3641404-3E4C-4E12-9D6B-6C0A2C6E1A01") // we notify/serve pending envelopes

    var onChat: ((ChatEnvelope) -> Void)?

    private var manager: CBPeripheralManager?
    private var locChar: CBMutableCharacteristic?
    private var chatOutChar: CBMutableCharacteristic?
    private var displayName = ""
    private var payload = Data()
    private var pendingOut: [ChatEnvelope] = []
    private var active = false

    func start(displayName: String) {
        Log.add("beacon", "start as \(displayName)")
        self.displayName = displayName
        active = true
        if manager == nil {
            manager = CBPeripheralManager(
                delegate: self, queue: nil,
                options: [CBPeripheralManagerOptionRestoreIdentifierKey: "locompass.beacon"])
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

    // MARK: chat outbox (served to subscribed centrals)
    func enqueueChat(_ env: ChatEnvelope) {
        guard active else { return }
        pendingOut.removeAll { $0.kind == .ack && Date().timeIntervalSince($0.ts) > 120 }
        if let i = pendingOut.firstIndex(where: { $0.id == env.id && $0.kind == env.kind }) {
            pendingOut[i] = env
        } else {
            pendingOut.append(env)
        }
        if pendingOut.count > 8 { pendingOut.removeFirst(pendingOut.count - 8) }
        pushChatOut()
    }

    func removePendingChat(id: String) {
        pendingOut.removeAll { $0.id == id && $0.kind == .chat }
        pushChatOut()
    }

    private var chatOutPayload: Data {
        (try? JSONEncoder().encode(pendingOut)) ?? Data()
    }

    private func pushChatOut() {
        if let c = chatOutChar {
            // May truncate at MTU — centrals fall back to a full read.
            manager?.updateValue(chatOutPayload, for: c, onSubscribedCentrals: nil)
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
        let chatIn = CBMutableCharacteristic(type: Self.chatInCharUUID, properties: .write,
                                             value: nil, permissions: .writeable)
        let chatOut = CBMutableCharacteristic(type: Self.chatOutCharUUID, properties: [.read, .notify],
                                              value: nil, permissions: .readable)
        locChar = loc
        chatOutChar = chatOut
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [name, loc, chatIn, chatOut]
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
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // iOS relaunched us after a system kill; didUpdateState → setup()
        // re-adds the service and re-advertises.
        Log.add("beacon", "state restored by iOS after background kill")
        active = true
    }

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
        Log.add("beacon", "a seeker subscribed (\(characteristic.uuid == Self.chatOutCharUUID ? "chat" : "position"))")
        if characteristic.uuid == Self.chatOutCharUUID { pushChatOut() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        Log.add("beacon", "a seeker unsubscribed")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let data: Data?
        switch request.characteristic.uuid {
        case Self.locCharUUID:     data = payload
        case Self.chatOutCharUUID: data = chatOutPayload
        default:                   data = nil
        }
        guard let data else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        guard request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        var ok = false
        for request in requests {
            if request.characteristic.uuid == Self.chatInCharUUID, let data = request.value,
               let env = try? JSONDecoder().decode(ChatEnvelope.self, from: data) {
                Log.add("beacon", "chat \(env.kind.rawValue) from \(env.from)")
                ok = true
                onChat?(env)
            }
        }
        if let first = requests.first {
            peripheral.respond(to: first, withResult: ok ? .success : .attributeNotFound)
        }
    }
}
