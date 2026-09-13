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
                    BatteryRow(
                        icon: "earbud.left",
                        label: "Left",
                        percentage: bluetoothManager.earbuds.batteryState.leftPercentage,
                        isCharging: bluetoothManager.earbuds.batteryState.isLeftCharging
                    )
                    BatteryRow(
                        icon: "earbud.right",
                        label: "Right",
                        percentage: bluetoothManager.earbuds.batteryState.rightPercentage,
                        isCharging: bluetoothManager.earbuds.batteryState.isRightCharging
                    )
                    
                    // Show Case battery only when the box is opened
                    if let casePct = bluetoothManager.earbuds.batteryState.casePercentage {
                        BatteryRow(
                            icon: "archivebox",
                            label: "Case",
                            percentage: casePct,
                            isCharging: bluetoothManager.earbuds.batteryState.isCaseCharging
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: bluetoothManager.earbuds.batteryState.casePercentage)
            } else {
                Text("Earbuds are disconnected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            Divider()
            
            HStack {
                if let lastSeen = bluetoothManager.earbuds.lastSeen {
                    Text("Last updated: \(lastSeen.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Last updated: ---")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    bluetoothManager.sendBatteryQuery()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh battery status")
                
                Button(action: {
                    openWindow(id: "settings-window")
                }) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Settings")
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
    var isCharging: Bool = false
    var emptyText: String = "In Case"
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24, alignment: .center)
                .foregroundColor(percentage != nil ? .primary : .secondary)
            Text(label)
                .frame(width: 50, alignment: .leading)
                .foregroundColor(percentage != nil ? .primary : .secondary)
            
            if let pct = percentage {
                ProgressView(value: Double(pct), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: colorForPercentage(pct)))
                
                HStack(spacing: 2) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    Text("\(pct)%")
                        .font(.subheadline.monospacedDigit())
                }
                .frame(width: 50, alignment: .trailing)
            } else {
                Text(emptyText)
                    .font(.caption)
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
