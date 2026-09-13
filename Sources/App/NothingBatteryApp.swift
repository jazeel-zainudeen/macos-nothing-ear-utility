import SwiftUI

@main
struct NothingBatteryApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra("NothingBattery", systemImage: "earbuds") {
            BatteryView(bluetoothManager: bluetoothManager)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(bluetoothManager: bluetoothManager)
        }
    }
}
