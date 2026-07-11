import Foundation
import CoreBluetooth

protocol FindableScannerDelegate: AnyObject {
    func scanner(_ s: FindableScanner, didUpdatePeer id: String,
                 name: String?, location: BeaconLocation?, rssi: Int?)
    func scanner(_ s: FindableScanner, didLosePeer id: String)
    func scanner(_ s: FindableScanner, didReceiveChat env: ChatEnvelope)
}

/// Foreground-side counterpart of FindableBeacon: scans for friends
/// broadcasting the Locompass service, connects, and streams their name,
/// GPS position, signal strength, and chat traffic.
final class FindableScanner: NSObject {
    weak var delegate: FindableScannerDelegate?
    /// Our display name — chat envelopes from beacons are filtered to us.
    var myName = ""

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var names: [UUID: String] = [:]
    private var chatInChars: [UUID: CBCharacteristic] = [:]
    private var rssiTimer: Timer?
    private var lastLocLog: [UUID: Date] = [:]

    func start() {
        if central == nil {
            central = CBCentralManager(
                delegate: self, queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "locompass.scanner"])
        } else {
            scan()
        }
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.peripherals.values.forEach { if $0.state == .connected { $0.readRSSI() } }
        }
    }

    func stop() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        central?.stopScan()
        peripherals.values.forEach { central?.cancelPeripheralConnection($0) }
        peripherals.removeAll()
        names.removeAll()
        chatInChars.removeAll()
    }

    /// Write a chat envelope to a connected beacon owned by `name`.
    /// Returns true if a write was issued.
    @discardableResult
    func sendChat(_ env: ChatEnvelope, toPersonNamed name: String) -> Bool {
        guard let data = try? JSONEncoder().encode(env) else { return false }
        for (uuid, n) in names where n == name {
            if let p = peripherals[uuid], p.state == .connected, let c = chatInChars[uuid] {
                p.writeValue(data, for: c, type: .withResponse)
                return true
            }
        }
        return false
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [FindableBeacon.serviceUUID], options: nil)
    }
}

extension FindableScanner: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Log.add("scan", "state restored by iOS after background kill")
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in restored {
                peripherals[p.identifier] = p
                p.delegate = self
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.add("scan", "bluetooth state: \(central.state.rawValue) (\(central.state == .poweredOn ? "on" : "not ready"))")
        if central.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripherals[peripheral.identifier] == nil else { return }
        Log.add("scan", "found beacon \(peripheral.identifier.uuidString.prefix(8)) rssi=\(RSSI.intValue)")
        peripherals[peripheral.identifier] = peripheral // retain, or the connect is dropped
        peripheral.delegate = self
        delegate?.scanner(self, didUpdatePeer: peripheral.identifier.uuidString,
                          name: nil, location: nil, rssi: RSSI.intValue)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Log.add("scan", "connected to \(peripheral.identifier.uuidString.prefix(8))")
        peripheral.discoverServices([FindableBeacon.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        Log.add("scan", "disconnected from \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "clean")")
        chatInChars[peripheral.identifier] = nil
        delegate?.scanner(self, didLosePeer: peripheral.identifier.uuidString)
        central.connect(peripheral) // may just be a dead spot in the crowd — keep trying
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        Log.add("scan", "connect failed \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "?")")
        peripherals[peripheral.identifier] = nil
        delegate?.scanner(self, didLosePeer: peripheral.identifier.uuidString)
    }
}

extension FindableScanner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == FindableBeacon.serviceUUID })
        else { return }
        peripheral.discoverCharacteristics(
            [FindableBeacon.nameCharUUID, FindableBeacon.locCharUUID,
             FindableBeacon.chatInCharUUID, FindableBeacon.chatOutCharUUID],
            for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        service.characteristics?.forEach { c in
            switch c.uuid {
            case FindableBeacon.nameCharUUID:
                peripheral.readValue(for: c)
            case FindableBeacon.locCharUUID:
                peripheral.setNotifyValue(true, for: c)
                peripheral.readValue(for: c)
            case FindableBeacon.chatInCharUUID:
                chatInChars[peripheral.identifier] = c
            case FindableBeacon.chatOutCharUUID:
                peripheral.setNotifyValue(true, for: c)
                peripheral.readValue(for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        let id = peripheral.identifier.uuidString
        switch characteristic.uuid {
        case FindableBeacon.nameCharUUID:
            let name = String(data: data, encoding: .utf8)
            Log.add("scan", "\(id.prefix(8)) is \"\(name ?? "?")\"")
            if let name { names[peripheral.identifier] = name }
            delegate?.scanner(self, didUpdatePeer: id, name: name, location: nil, rssi: nil)
        case FindableBeacon.locCharUUID:
            let loc = try? JSONDecoder().decode(BeaconLocation.self, from: data)
            if Date().timeIntervalSince(lastLocLog[peripheral.identifier] ?? .distantPast) > 15 {
                lastLocLog[peripheral.identifier] = Date()
                Log.add("scan", "\(id.prefix(8)) position update (\(loc == nil ? "undecodable" : "ok"))")
            }
            delegate?.scanner(self, didUpdatePeer: id, name: nil, location: loc, rssi: nil)
        case FindableBeacon.chatOutCharUUID:
            if let envs = try? JSONDecoder().decode([ChatEnvelope].self, from: data) {
                for env in envs where env.to == myName {
                    delegate?.scanner(self, didReceiveChat: env)
                }
            } else if !data.isEmpty {
                // Notification truncated at MTU — fetch the full value.
                peripheral.readValue(for: characteristic)
            }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            Log.add("scan", "chat write failed: \(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        delegate?.scanner(self, didUpdatePeer: peripheral.identifier.uuidString,
                          name: nil, location: nil, rssi: RSSI.intValue)
    }
}
