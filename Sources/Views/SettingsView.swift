import SwiftUI

struct SettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            DiagnosticsView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Advanced", systemImage: "ladybug")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("lowBatteryAlerts") private var lowBatteryAlerts = true
    
    var body: some View {
        Form {
            Section(header: Text("Startup")) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            
            Section(header: Text("Notifications")) {
                Toggle("Enable low battery notifications", isOn: $lowBatteryAlerts)
            }
        }
        .padding()
    }
}
