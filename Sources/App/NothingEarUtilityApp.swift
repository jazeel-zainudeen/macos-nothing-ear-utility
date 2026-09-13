import SwiftUI

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
        if bluetoothManager.earbuds.connectionState == .connected {
            let leftPct = bluetoothManager.earbuds.batteryState.leftPercentage
            let rightPct = bluetoothManager.earbuds.batteryState.rightPercentage
            
            HStack(spacing: 6) {
                // Left Earbud: full opacity if connected, light colored if disconnected
                HStack(spacing: 2) {
                    Image(systemName: "earbud.left")
                        .opacity(leftPct != nil ? 1.0 : 0.35)
                    if let l = leftPct {
                        Image(systemName: batteryIcon(for: l))
                    }
                }
                
                // Right Earbud: full opacity if connected, light colored if disconnected
                HStack(spacing: 2) {
                    Image(systemName: "earbud.right")
                        .opacity(rightPct != nil ? 1.0 : 0.35)
                    if let r = rightPct {
                        Image(systemName: batteryIcon(for: r))
                    }
                }
            }
        } else {
            Image(systemName: "earbuds")
        }
    }
    
    private func batteryIcon(for percentage: Int) -> String {
        switch percentage {
        case 90...100: return "battery.100"
        case 65..<90: return "battery.75"
        case 35..<65: return "battery.50"
        case 10..<35: return "battery.25"
        default: return "battery.0"
        }
    }
}
