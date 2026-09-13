import SwiftUI

@main
struct NothingEarUtilityApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra("Nothing Ear Utility", systemImage: "earbuds") {
            BatteryView(bluetoothManager: bluetoothManager)
        }
        .menuBarExtraStyle(.window)
        
        Window("Settings", id: "settings-window") {
            SettingsView(bluetoothManager: bluetoothManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 450, height: 300)
    }
}
