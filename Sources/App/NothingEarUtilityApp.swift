import SwiftUI

@main
struct NothingEarUtilityApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra {
            BatteryView(bluetoothManager: bluetoothManager)
        } label: {
            if bluetoothManager.earbuds.connectionState == .connected {
                let name = bluetoothManager.earbuds.name
                let l = bluetoothManager.earbuds.batteryState.leftPercentage
                let r = bluetoothManager.earbuds.batteryState.rightPercentage
                let text: String
                if let l = l, let r = r {
                    text = "\(name)  L:\(l)%  R:\(r)%"
                } else if let l = l {
                    text = "\(name)  L:\(l)%"
                } else if let r = r {
                    text = "\(name)  R:\(r)%"
                } else {
                    text = name
                }
                Label(text, systemImage: "earbuds")
            } else {
                Image(systemName: "earbuds")
            }
        }
        .menuBarExtraStyle(.window)
        
        Window("Settings", id: "settings-window") {
            SettingsView(bluetoothManager: bluetoothManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 450, height: 300)
    }
}
