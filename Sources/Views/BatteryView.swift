import SwiftUI
import AppKit

struct BatteryView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(bluetoothManager.earbuds.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(bluetoothManager.earbuds.connectionState == .connected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(bluetoothManager.earbuds.connectionState.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)
            
            Divider()
            
            if bluetoothManager.earbuds.connectionState == .connected {
                VStack(spacing: 6) {
                    BatteryRow(
                        image: NothingEarAssets.leftBud,
                        label: "Left",
                        percentage: bluetoothManager.earbuds.batteryState.leftPercentage,
                        isCharging: bluetoothManager.earbuds.batteryState.isLeftCharging,
                        emptyText: "In Case"
                    )
                    
                    BatteryRow(
                        image: NothingEarAssets.rightBud,
                        label: "Right",
                        percentage: bluetoothManager.earbuds.batteryState.rightPercentage,
                        isCharging: bluetoothManager.earbuds.batteryState.isRightCharging,
                        emptyText: "In Case"
                    )
                    
                    BatteryRow(
                        image: NothingEarAssets.caseBox,
                        label: "Case",
                        percentage: bluetoothManager.earbuds.batteryState.casePercentage,
                        isCharging: bluetoothManager.earbuds.batteryState.isCaseCharging,
                        emptyText: bluetoothManager.earbuds.batteryState.isCaseCharging ? "Charging" : "In Case"
                    )
                }
            } else {
                VStack(spacing: 6) {
                    BatteryRow(
                        image: NothingEarAssets.leftBud,
                        label: "Left",
                        percentage: nil,
                        isCharging: false,
                        emptyText: "---"
                    )
                    BatteryRow(
                        image: NothingEarAssets.rightBud,
                        label: "Right",
                        percentage: nil,
                        isCharging: false,
                        emptyText: "---"
                    )
                    BatteryRow(
                        image: NothingEarAssets.caseBox,
                        label: "Case",
                        percentage: nil,
                        isCharging: false,
                        emptyText: "---"
                    )
                }
                .opacity(0.6)
            }
            
            Divider()
            
            // Footer
            HStack {
                if bluetoothManager.isRefreshing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Refreshing...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if bluetoothManager.justRefreshed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11))
                        Text("Updated just now")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else if let lastSeen = bluetoothManager.earbuds.lastSeen {
                    Text("Last updated: \(lastSeen.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                } else {
                    Text("Last updated: Just now")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
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
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "settings-window")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            for w in NSApp.windows {
                                if w.identifier?.rawValue == "settings-window" || w.title == "Settings" || (!w.className.contains("StatusBar") && !w.className.contains("MenuBarExtra") && w.canBecomeKey) {
                                    if w.isMiniaturized {
                                        w.deminiaturize(nil)
                                    }
                                    w.makeKeyAndOrderFront(nil)
                                    w.orderFrontRegardless()
                                }
                            }
                        }
                    }
                    
                    MenuIconButton(
                        icon: "power",
                        tooltip: "Quit Nothing Ear Utility",
                        isDestructive: true
                    ) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.isRefreshing)
            .animation(.easeInOut(duration: 0.2), value: bluetoothManager.justRefreshed)
        }
        .padding(14)
        .frame(width: 290)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDestructive ? (isHovered ? .red : .secondary) : (isHovered ? .primary : .secondary))
                .rotationEffect(.degrees(spinAngle))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? (isDestructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.08)) : Color.clear)
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
        .onChange(of: isLoading) { loading in
            if loading {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle += 360
                }
            }
        }
    }
}

struct BatteryRow: View {
    var image: NSImage
    var label: String
    var percentage: Int?
    var isCharging: Bool = false
    var emptyText: String = "In Case"
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .opacity(percentage != nil ? 1.0 : 0.6)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(percentage != nil ? .primary : .secondary)
                .frame(width: 44, alignment: .leading)
            
            if let pct = percentage {
                ProgressView(value: Double(pct), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: colorForPercentage(pct)))
                
                HStack(spacing: 3) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                    Text("\(pct)%")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                }
                .frame(width: 52, alignment: .trailing)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 4)
                
                Text(emptyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 32)
    }
    
    private func colorForPercentage(_ percentage: Int) -> Color {
        switch percentage {
        case 60...100: return .green
        case 30..<60: return .yellow
        default: return .red
        }
    }
}
