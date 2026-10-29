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
    private enum GATTOperation { case read, write(Data), subscribe }
    private var gattPeripheral: CBPeripheral?
    private var gattService: CBUUID?
    private var gattCharacteristic: CBUUID?
    private var gattOperation: GATTOperation?
    private var gattCallback: ((Result<[String: Any], Error>) -> Void)?
    private var gattTimeout: Task<Void, Never>?
    private var notificationSink: (([String: Any]) -> Void)?

    func gatt(deviceID: String, service: String, characteristic: String,
              writeData: Data?, subscribe: Bool = false,
              onNotification: (([String: Any]) -> Void)? = nil,
              completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard gattCallback == nil, batteryCallback == nil, notificationSink == nil,
              let id = UUID(uuidString: deviceID),
              let peripheral = peripherals[id],
              let manager, manager.state == .poweredOn,
              Self.validUUID(service), Self.validUUID(characteristic),
              (writeData?.count ?? 0) <= 512 else {
            completion(.failure(NSError(domain: "HTMLAppBluetooth", code: 11,
              userInfo: [NSLocalizedDescriptionKey: "Scan for a BLE device first and provide valid service/characteristic UUIDs (write limit 512 bytes)."])))
            return
        }
        gattPeripheral = peripheral
        gattService = CBUUID(string: service)
        gattCharacteristic = CBUUID(string: characteristic)
        gattOperation = subscribe ? .subscribe : (writeData.map { .write($0) } ?? .read)
        notificationSink = subscribe ? onNotification : nil
        gattCallback = completion
        peripheral.delegate = self
        manager.connect(peripheral, options: nil)
        gattTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 12,
              userInfo: [NSLocalizedDescriptionKey: "GATT operation timed out."])))
        }
    }

    private static func validUUID(_ value: String) -> Bool {
        let characters = CharacterSet(charactersIn: "0123456789ABCDEFabcdef-")
        return [4, 8, 36].contains(value.count) &&
            value.unicodeScalars.allSatisfy { characters.contains($0) }
    }

    private func finishGATT(_ result: Result<[String: Any], Error>) {
        gattTimeout?.cancel()
        gattTimeout = nil
        if let peripheral = gattPeripheral { manager?.cancelPeripheralConnection(peripheral) }
        gattPeripheral = nil
        gattService = nil
        gattCharacteristic = nil
        gattOperation = nil
        notificationSink = nil
        let callback = gattCallback
        gattCallback = nil
        callback?(result)
    }

    private let batteryService = CBUUID(string: "180F")
    private let batteryCharacteristic = CBUUID(string: "2A19")

    func readBattery(deviceID: String, completion: @escaping (Result<Int, Error>) -> Void) {
        guard batteryCallback == nil, gattCallback == nil, notificationSink == nil,
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
        if gattPeripheral === peripheral, let service = gattService {
            peripheral.discoverServices([service])
            return
        }
        guard batteryPeripheral === peripheral else { return }
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        if gattPeripheral === peripheral {
            finishGATT(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 13)))
            return
        }
        guard batteryPeripheral === peripheral else { return }
        finishBattery(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 5)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if gattPeripheral === peripheral, gattCallback != nil {
            finishGATT(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 14)))
            return
        }
        guard batteryPeripheral === peripheral, batteryCallback != nil else { return }
        finishBattery(.failure(error ?? NSError(domain: "HTMLAppBluetooth", code: 6)))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if gattPeripheral === peripheral, let expected = gattService, let wanted = gattCharacteristic {
            guard error == nil,
                  let service = peripheral.services?.first(where: { $0.uuid == expected }) else {
                finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 15,
                    userInfo: [NSLocalizedDescriptionKey: "GATT service unavailable."])))
                return
            }
            peripheral.discoverCharacteristics([wanted], for: service)
            return
        }
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
        if gattPeripheral === peripheral, let expected = gattCharacteristic {
            guard error == nil,
                  let characteristic = service.characteristics?.first(where: { $0.uuid == expected }),
                  let operation = gattOperation else {
                finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 16,
                    userInfo: [NSLocalizedDescriptionKey: "GATT characteristic unavailable."])))
                return
            }
            switch operation {
            case .subscribe:
                guard characteristic.properties.contains(.notify) ||
                      characteristic.properties.contains(.indicate) else {
                    finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 21,
                        userInfo: [NSLocalizedDescriptionKey: "Characteristic does not support notifications."])))
                    return
                }
                peripheral.setNotifyValue(true, for: characteristic)
            case .read:
                guard characteristic.properties.contains(.read) else {
                    finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 17,
                        userInfo: [NSLocalizedDescriptionKey: "Characteristic cannot be read."])))
                    return
                }
                peripheral.readValue(for: characteristic)
            case .write(let data):
                guard characteristic.properties.contains(.write) else {
                    finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 18,
                        userInfo: [NSLocalizedDescriptionKey: "Characteristic does not allow confirmed writes."])))
                    return
                }
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
            return
        }
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
        if gattPeripheral === peripheral, notificationSink != nil,
           gattCallback == nil, case .subscribe = gattOperation {
            if let error {
                notificationSink?(["error": error.localizedDescription])
                finishGATT(.failure(error))
            } else if let value = characteristic.value {
                notificationSink?([
                    "deviceID": peripheral.identifier.uuidString,
                    "dataBase64": value.base64EncodedString(),
                    "characteristic": characteristic.uuid.uuidString
                ])
            }
            return
        }
        if gattPeripheral === peripheral, gattCallback != nil {
            if let error {
                finishGATT(.failure(error))
            } else if let value = characteristic.value {
                finishGATT(.success([
                    "dataBase64": value.base64EncodedString(),
                    "byteCount": value.count,
                    "service": gattService?.uuidString ?? "",
                    "characteristic": characteristic.uuid.uuidString
                ]))
            } else {
                finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 19,
                    userInfo: [NSLocalizedDescriptionKey: "Characteristic had no readable data."])))
            }
            return
        }
        guard batteryPeripheral === peripheral else { return }
        guard error == nil, let value = characteristic.value, let level = value.first,
              level <= 100 else {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Battery reading is unavailable."])))
            return
        }
        finishBattery(.success(Int(level)))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard gattPeripheral === peripheral, gattCallback != nil,
              case .subscribe = gattOperation else { return }
        if let error {
            finishGATT(.failure(error))
        } else if characteristic.isNotifying {
            gattTimeout?.cancel()
            gattTimeout = nil
            let callback = gattCallback
            gattCallback = nil
            callback?(.success(["subscribed": true, "deviceID": peripheral.identifier.uuidString]))
        } else {
            finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 22,
                userInfo: [NSLocalizedDescriptionKey: "BLE subscription could not be activated."])))
        }
    }

    func stopSubscription() {
        if let peripheral = gattPeripheral {
            manager?.cancelPeripheralConnection(peripheral)
        }
        if gattCallback != nil {
            finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 23,
                userInfo: [NSLocalizedDescriptionKey: "BLE subscription cancelled."])))
        } else {
            gattPeripheral = nil
            gattService = nil
            gattCharacteristic = nil
            gattOperation = nil
            notificationSink = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard gattPeripheral === peripheral, gattCallback != nil else { return }
        if let error { finishGATT(.failure(error)) }
        else { finishGATT(.success(["written": true, "characteristic": characteristic.uuid.uuidString])) }
    }

    func scan(seconds: Double, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard self.completion == nil, notificationSink == nil, gattCallback == nil else {
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
        if gattCallback == nil && notificationSink != nil { stopSubscription() }
        if gattCallback != nil {
            finishGATT(.failure(NSError(domain: "HTMLAppBluetooth", code: 20,
                userInfo: [NSLocalizedDescriptionKey: "BLE operation cancelled."])))
        }
        if batteryCallback != nil {
            finishBattery(.failure(NSError(domain: "HTMLAppBluetooth", code: 10)))
        }
    }
}
