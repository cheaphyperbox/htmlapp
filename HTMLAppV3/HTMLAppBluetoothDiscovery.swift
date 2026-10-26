import Foundation
import CoreBluetooth

/// Time-bounded BLE advertisement discovery (not arbitrary Classic Bluetooth
/// enumeration). User permission is checked by HTMLNativeAPIBridge first.
@MainActor
final class HTMLAppBluetoothDiscovery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var manager: CBCentralManager?
    private var discovered: [UUID: [String: Any]] = [:]
    private var completion: ((Result<[[String: Any]], Error>) -> Void)?
    private var timeout: Task<Void, Never>?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var batteryPeripheral: CBPeripheral?
    private var batteryCallback: ((Result<Int, Error>) -> Void)?
    private var batteryTimeout: Task<Void, Never>?
    private let batteryService = CBUUID(string: "180F")
    private let batteryCharacteristic = CBUUID(string: "2A19")

    func readBattery(deviceID: String, completion: @escaping (Result<Int, Error>) -> Void) {
        guard batteryCallback == nil,
              let uuid = UUID(uuidString: deviceID),
              let peripheral = peripherals[uuid],
              let manager, manager.state == .poweredOn else {
            completion(.failure(NSError(domain: "HTMLAppBluetooth", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Scan for this BLE device first."])))
            return
        }
        batteryPeripheral = peripheral
        batteryCallback = completion
        peripheral.delegate = self
        manager.connect(peripheral, options: nil)
        batteryTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "BLE battery read timed out."])))
        }
    }

    private func finishBattery(_ result: Result<Int, Error>) {
        batteryTimeout?.cancel()
        batteryTimeout = nil
        if let peripheral = batteryPeripheral { manager?.cancelPeripheralConnection(peripheral) }
        batteryPeripheral = nil
        let callback = batteryCallback
        batteryCallback = nil
        callback?(result)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard batteryPeripheral === peripheral else { return }
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard batteryPeripheral === peripheral else { return }
        finishBattery(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 5)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard batteryPeripheral === peripheral, batteryCallback != nil else { return }
        finishBattery(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 6)))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard batteryPeripheral === peripheral else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == batteryService }) else {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Device does not expose the standard BLE Battery Service."])))
            return
        }
        peripheral.discoverCharacteristics([batteryCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard batteryPeripheral === peripheral else { return }
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == batteryCharacteristic }),
              characteristic.properties.contains(.read) else {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Device battery level is not readable."])))
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard batteryPeripheral === peripheral else { return }
        guard error == nil, let value = characteristic.value, let level = value.first,
              level <= 100 else {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Battery reading is unavailable."])))
            return
        }
        finishBattery(.success(Int(level)))
    }

    func scan(seconds: Double, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard self.completion == nil else {
            completion(.failure(NSError(domain: "HTMLAppBluetooth", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "A Bluetooth scan is already running."])))
            return
        }
        self.completion = completion
        discovered = [:]
        peripherals = [:]
        if manager == nil { manager = CBCentralManager(delegate: self, queue: nil) }
        else { centralManagerDidUpdateState(manager!) }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(12, max(2, seconds)) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if completion != nil {
                central.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
            }
        case .poweredOff, .unauthorized, .unsupported:
            fail("Bluetooth is unavailable, disabled, or denied in iOS Settings.")
        case .resetting, .unknown:
            break // Keep waiting only until the bounded timeout.
        @unknown default: fail("Bluetooth is unavailable.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard completion != nil, discovered.count < 40 else { return }
        peripherals[peripheral.identifier] = peripheral
        discovered[peripheral.identifier] = [
            "id": peripheral.identifier.uuidString,
            "name": peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unnamed device"),
            "rssi": RSSI.intValue
        ]
    }

    private func finish() {
        manager?.stopScan()
        timeout?.cancel()
        timeout = nil
        let callback = completion
        completion = nil
        callback?(.success(Array(discovered.values)))
    }

    private func fail(_ message: String) {
        manager?.stopScan()
        timeout?.cancel()
        timeout = nil
        let callback = completion
        completion = nil
        callback?(.failure(NSError(domain: "HTMLAppBluetooth", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: message])))
    }

    func cancel() {
        manager?.stopScan()
        timeout?.cancel()
        timeout = nil
        completion = nil
        if batteryCallback != nil {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 10)))
        }
    }
}
