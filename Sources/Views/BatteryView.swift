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
                    
                    // Show Case battery when the box is opened or when charging
                    if let casePct = bluetoothManager.earbuds.batteryState.casePercentage {
                        BatteryRow(
                            icon: "archivebox",
                            label: "Case",
                            percentage: casePct,
                            isCharging: bluetoothManager.earbuds.batteryState.isCaseCharging
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if bluetoothManager.earbuds.batteryState.isCaseCharging {
                        BatteryRow(
                            icon: "archivebox",
                            label: "Case",
                            percentage: nil,
                            isCharging: true,
                            emptyText: "Charging"
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: bluetoothManager.earbuds.batteryState.casePercentage != nil || bluetoothManager.earbuds.batteryState.isCaseCharging)
            } else {
                Text("Earbuds are disconnected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
            
            Divider()
            
            HStack {
                if bluetoothManager.isRefreshing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if bluetoothManager.justRefreshed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("Updated just now")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if let lastSeen = bluetoothManager.earbuds.lastSeen {
                    Text("Last updated: \(lastSeen.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                } else {
                    Text("Last updated: ---")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
                
                Spacer()
                
                MenuIconButton(
                    icon: "arrow.clockwise",
                    tooltip: "Refresh battery status",
                    isLoading: bluetoothManager.isRefreshing
                ) {
                    bluetoothManager.sendBatteryQuery()
                }
                
                MenuIconButton(
                    icon: "gearshape",
                    tooltip: "Settings"
                ) {
                    openWindow(id: "settings-window")
                }
                
                MenuIconButton(
                    icon: "power",
                    tooltip: "Quit Nothing Ear Utility",
                    isDestructive: true
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.isRefreshing)
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.justRefreshed)
        }
        .padding()
        .frame(width: 280)
    }
}

struct MenuIconButton: View {
    let icon: String
    let tooltip: String
    var isDestructive: Bool = false
    var isLoading: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var spinAngle: Double = 0
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.6)) {
                spinAngle += 360
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDestructive ? (isHovered ? .red : .secondary) : (isHovered ? .primary : .secondary))
                .rotationEffect(.degrees(spinAngle))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? (isDestructive ? Color.red.opacity(0.15) : Color.primary.opacity(0.1)) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isHovered ? (isDestructive ? Color.red.opacity(0.25) : Color.primary.opacity(0.15)) : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
                HStack(spacing: 4) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("Charging")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(emptyText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
