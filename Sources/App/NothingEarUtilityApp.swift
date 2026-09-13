import SwiftUI
import AppKit

@main
struct NothingEarUtilityApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra {
            BatteryView(bluetoothManager: bluetoothManager)
        } label: {
            MenuBarIconView(bluetoothManager: bluetoothManager)
        }
        .menuBarExtraStyle(.window)
        
        Window("Settings", id: "settings-window") {
            SettingsView(bluetoothManager: bluetoothManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 450, height: 300)
    }
}

struct MenuBarIconView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        Image(nsImage: bluetoothManager.menuBarImage)
    }
}
