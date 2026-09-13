import Foundation
import CoreBluetooth
import IOBluetooth
import Combine

public class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published public var earbuds: Earbuds
    @Published public var discoveredServices: [String] = []
    
    private var centralManager: CBCentralManager!
    private var blePeripheral: CBPeripheral?
    private var pollTimer: Timer?
    
    // Known Nothing device name patterns
    private let nothingNamePatterns = ["Nothing Ear", "Ear (1)", "Ear (2)", "Ear (a)", "Ear (stick)", "Nothing"]
    
    public override init() {
        self.earbuds = Earbuds(name: "Nothing Ear", connectionState: .disconnected)
        super.init()
        
        // Also start CoreBluetooth for BLE advertisement data (battery via Fast Pair)
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
        
        // Defer initial scan to let SwiftUI set up observation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.findPairedNothingDevice()
        }
        
        // Poll for paired device status periodically
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.findPairedNothingDevice()
        }
    }
    
    deinit {
        pollTimer?.invalidate()
    }
    
    // MARK: - IOBluetooth (Classic Bluetooth - finds paired devices)
    
    private func findPairedNothingDevice() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            print("[NothingEar] Failed to get paired devices list")
            return
        }
        
        print("[NothingEar] Found \(pairedDevices.count) paired devices:")
        for device in pairedDevices {
            let name = device.name ?? "(no name)"
            let connected = device.isConnected()
            print("[NothingEar]   - '\(name)' connected=\(connected)")
        }
        
        for device in pairedDevices {
            let name = device.name ?? ""
            if isNothingDevice(name: name) {
                print("[NothingEar] Matched Nothing device: '\(name)'")
                DispatchQueue.main.async {
                    self.earbuds.name = name
                    
                    if device.isConnected() {
                        self.earbuds.connectionState = .connected
                        self.earbuds.lastSeen = Date()
                        
                        // Add device info to diagnostics
                        self.updateDiagnostics(device: device)
                    } else {
                        self.earbuds.connectionState = .disconnected
                    }
                }
                return
            }
        }
        print("[NothingEar] No Nothing device found among paired devices")
    }
    
    private func isNothingDevice(name: String) -> Bool {
        return nothingNamePatterns.contains { name.localizedCaseInsensitiveContains($0) }
    }
    
    private func updateDiagnostics(device: IOBluetoothDevice) {
        var info: [String] = []
        info.append("Device: \(device.name ?? "Unknown")")
        info.append("Address: \(device.addressString ?? "Unknown")")
        info.append("Connected: \(device.isConnected())")
        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for service in services {
                if let dict = service.attributes as? [NSNumber: Any] {
                    info.append("SDP Service: \(dict.count) attributes")
                }
            }
        }
        DispatchQueue.main.async {
            self.discoveredServices = info
        }
    }
    
    // MARK: - CoreBluetooth (BLE - for Fast Pair battery advertisements)
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startBLEScanning()
        }
    }
    
    private func startBLEScanning() {
        // Scan for Fast Pair advertisements to get battery data
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        guard isNothingDevice(name: name) else { return }
        
        // Try to parse Fast Pair battery data from advertisement
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            if let fastPairData = serviceData[NothingEarProtocol.fastPairServiceUUID] {
                if let newBatteryState = NothingEarProtocol.parseFastPairBatteryData(fastPairData) {
                    DispatchQueue.main.async {
                        self.earbuds.batteryState = newBatteryState
                        self.earbuds.lastSeen = Date()
                    }
                }
            }
        }
        
        // Optionally connect via BLE to discover services
        if self.blePeripheral == nil {
            self.blePeripheral = peripheral
            self.blePeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.blePeripheral = nil
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            DispatchQueue.main.async {
                self.discoveredServices.append("BLE Service: \(service.uuid.uuidString)")
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            DispatchQueue.main.async {
                self.discoveredServices.append("  Char: \(char.uuid.uuidString)")
            }
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        print("Data from \(characteristic.uuid.uuidString): \(hex)")
    }
}
