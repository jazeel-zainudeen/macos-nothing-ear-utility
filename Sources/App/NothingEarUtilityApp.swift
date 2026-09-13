import SwiftUI

@main
struct NothingEarUtilityApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra("Nothing Ear Utility", systemImage: "earbuds") {
            BatteryView(bluetoothManager: bluetoothManager)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(bluetoothManager: bluetoothManager)
        }
    }
}
