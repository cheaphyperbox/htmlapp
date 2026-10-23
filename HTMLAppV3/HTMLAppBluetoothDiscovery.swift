import Foundation
import CoreBluetooth

/// Time-bounded BLE advertisement discovery (not arbitrary Classic Bluetooth
/// enumeration). User permission is checked by HTMLNativeAPIBridge first.
@MainActor
final class HTMLAppBluetoothDiscovery: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var discovered: [UUID: [String: Any]] = [:]
    private var completion: ((Result<[[String: Any]], Error>) -> Void)?
    private var timeout: Task<Void, Never>?

    func scan(seconds: Double, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard self.completion == nil else {
            completion(.failure(NSError(domain: "HTMLAppBluetooth", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "A Bluetooth scan is already running."])))
            return
        }
        self.completion = completion
        discovered = [:]
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
    }
}
