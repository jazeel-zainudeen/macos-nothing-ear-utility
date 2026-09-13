import SwiftUI

@main
struct NothingEarUtilityApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        MenuBarExtra {
            BatteryView(bluetoothManager: bluetoothManager)
        } label: {
            if bluetoothManager.earbuds.connectionState == .connected {
                Label(menuBarText, systemImage: "earbuds")
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

extension NothingEarUtilityApp {
    private var menuBarText: String {
        let name = bluetoothManager.earbuds.name
        guard bluetoothManager.earbuds.connectionState == .connected else { return name }
        let l = bluetoothManager.earbuds.batteryState.leftPercentage
        let r = bluetoothManager.earbuds.batteryState.rightPercentage
        if let l = l, let r = r {
            return "\(name)  L:\(l)%  R:\(r)%"
        } else if let l = l {
            return "\(name)  L:\(l)%"
        } else if let r = r {
            return "\(name)  R:\(r)%"
        } else {
            return name
        }
    }
}
