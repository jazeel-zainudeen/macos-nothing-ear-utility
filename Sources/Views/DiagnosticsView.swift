import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bluetooth Diagnostics")
                .font(.headline)
            
            Text("Use this screen to inspect discovered services and characteristics for the Nothing Ear (2).")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if bluetoothManager.discoveredServices.isEmpty {
                List {
                    Text("No data available yet.")
                }
            } else {
                List(bluetoothManager.discoveredServices, id: \.self) { item in
                    Text(item)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
            HStack {
                Spacer()
                Button("Export Diagnostics") {
                    let data = bluetoothManager.discoveredServices.joined(separator: "\n")
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(data, forType: .string)
                }
            }
        }
        .padding()
    }
}
