import SwiftUI

struct BatteryView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bluetoothManager.earbuds.name)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(bluetoothManager.earbuds.connectionState == .connected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(bluetoothManager.earbuds.connectionState.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            if bluetoothManager.earbuds.connectionState == .connected {
                VStack(spacing: 8) {
                    BatteryRow(icon: "earbuds", label: "Left", percentage: bluetoothManager.earbuds.batteryState.leftPercentage)
                    BatteryRow(icon: "earbuds", label: "Right", percentage: bluetoothManager.earbuds.batteryState.rightPercentage)
                    BatteryRow(icon: "archivebox", label: "Case", percentage: bluetoothManager.earbuds.batteryState.casePercentage)
                }
            } else {
                Text("Earbuds are disconnected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            Divider()
            
            HStack {
                Text("Last updated: Just now")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    openWindow(id: "settings-window")
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct BatteryRow: View {
    var icon: String
    var label: String
    var percentage: Int?
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24, alignment: .center)
            Text(label)
                .frame(width: 50, alignment: .leading)
            
            if let pct = percentage {
                ProgressView(value: Double(pct), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: colorForPercentage(pct)))
                Text("\(pct)%")
                    .frame(width: 40, alignment: .trailing)
                    .font(.subheadline.monospacedDigit())
            } else {
                Text("---")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func colorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 60...100: return .green
        case 30..<60: return .yellow
        default: return .red
        }
    }
}
