import Foundation
import CoreBluetooth
import Combine

public class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published public var earbuds: Earbuds
    @Published public var discoveredServices: [String] = []
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    public override init() {
        self.earbuds = Earbuds(name: "Nothing Ear (2)", connectionState: .disconnected)
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            earbuds.connectionState = .disconnected
        }
    }
    
    private func startScanning() {
        // Scanning for Fast Pair and custom Nothing service
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if name.contains("Ear (2)") || name.contains("Nothing") {
            
            if self.peripheral == nil {
                self.peripheral = peripheral
                self.peripheral?.delegate = self
                earbuds.name = name
                earbuds.connectionState = .connecting
                centralManager.connect(peripheral, options: nil)
            }
            
            // Check for Fast Pair battery data in advertisement packet
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
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.earbuds.connectionState = .connected
            self.earbuds.lastSeen = Date()
            
            // Fallback mock data if real data isn't received yet
            if self.earbuds.batteryState.leftPercentage == nil {
                self.earbuds.batteryState = BatteryState(leftPercentage: 100, rightPercentage: 100, casePercentage: nil)
            }
        }
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.earbuds.connectionState = .disconnected
            self.peripheral = nil
            // Re-scan
            self.startScanning()
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            DispatchQueue.main.async {
                self.discoveredServices.append("Service: \(service.uuid.uuidString)")
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
        // Future: parse custom payload from Nothing Service
        let hex = data.map { String(format: "%02x", $0) }.joined()
        print("Data from \(characteristic.uuid.uuidString): \(hex)")
    }
}
