import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        TabView {
            NoiseControlSettingsView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Noise Control", systemImage: "waveform")
                }
            
            SoundSettingsView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Equalizer", systemImage: "slider.vertical.3")
                }
            
            EarbudFeaturesView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Features", systemImage: "earbuds")
                }
            
            GeneralSettingsView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            DiagnosticsView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Diagnostics", systemImage: "ladybug")
                }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Noise Control Settings
struct NoiseControlSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Header showing paired earbuds with authentic icons
            HStack(spacing: 32) {
                VStack(spacing: 6) {
                    NothingEarbudIconView(isLeft: true, size: 44)
                    Text("Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let p = bluetoothManager.earbuds.batteryState.leftPercentage {
                        Text("\(p)%")
                            .font(.caption.monospacedDigit().bold())
                    } else {
                        Text("In Case")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(spacing: 6) {
                    NothingCaseIconView(size: 44)
                    Text("Case")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let p = bluetoothManager.earbuds.batteryState.casePercentage {
                        Text("\(p)%")
                            .font(.caption.monospacedDigit().bold())
                    } else {
                        Text("In Case")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(spacing: 6) {
                    NothingEarbudIconView(isLeft: false, size: 44)
                    Text("Right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let p = bluetoothManager.earbuds.batteryState.rightPercentage {
                        Text("\(p)%")
                            .font(.caption.monospacedDigit().bold())
                    } else {
                        Text("In Case")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 10)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Active Noise Control")
                    .font(.headline)
                
                // ANC Mode Selector
                Picker("ANC Mode", selection: Binding(
                    get: { bluetoothManager.ancMode },
                    set: { bluetoothManager.setANCMode($0) }
                )) {
                    ForEach(NothingEarProtocol.ANCMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(modeDescription(bluetoothManager.ancMode))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 32, alignment: .topLeading)
                
                if bluetoothManager.earbuds.connectionState != .connected {
                    Text("Connect your Nothing Ear to adjust hardware noise control.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private func modeDescription(_ mode: NothingEarProtocol.ANCMode) -> String {
        switch mode {
        case .high:
            return "Maximum noise cancellation for loud environments such as flights or transit."
        case .mid:
            return "Balanced noise cancellation for cafes and offices."
        case .low:
            return "Subtle noise cancellation for quiet environments."
        case .adaptive:
            return "Automatically adjusts cancellation strength according to real-time ambient noise."
        case .transparency:
            return "Amplifies external ambient sounds so you can hear conversations and surroundings clearly."
        case .off:
            return "Microphone processing disabled for extended battery life."
        }
    }
}

// MARK: - Sound & Equalizer Settings
struct SoundSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        Form {
            Section(header: Text("Equalizer Presets")) {
                Picker("Sound Profile", selection: Binding(
                    get: { bluetoothManager.eqPreset },
                    set: { bluetoothManager.setEQPreset($0) }
                )) {
                    ForEach(NothingEarProtocol.EQPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Text("Bass Enhance")) {
                Toggle("Enable Bass Enhance", isOn: Binding(
                    get: { bluetoothManager.bassEnhanceEnabled },
                    set: { bluetoothManager.setEnhancedBass(enabled: $0, level: bluetoothManager.bassEnhanceLevel) }
                ))
                
                if bluetoothManager.bassEnhanceEnabled {
                    HStack {
                        Text("Intensity")
                        Slider(
                            value: Binding(
                                get: { Double(bluetoothManager.bassEnhanceLevel) },
                                set: { bluetoothManager.setEnhancedBass(enabled: true, level: Int($0)) }
                            ),
                            in: 1...5,
                            step: 1
                        )
                        Text("Level \(bluetoothManager.bassEnhanceLevel)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Earbud Features
struct EarbudFeaturesView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        Form {
            Section(header: Text("Smart Controls")) {
                Toggle(isOn: Binding(
                    get: { bluetoothManager.inEarDetectionEnabled },
                    set: { bluetoothManager.setInEarDetection(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In-Ear Detection")
                        Text("Automatically pauses playback when you remove an earbud.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { bluetoothManager.lowLatencyEnabled },
                    set: { bluetoothManager.setLowLatency(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low Lag Mode")
                        Text("Reduces audio latency for gaming and real-time streaming.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Find My Earbuds")) {
                HStack(spacing: 16) {
                    Button(action: {
                        bluetoothManager.ringBud(isLeft: true, ring: !bluetoothManager.isRingingLeft)
                    }) {
                        HStack {
                            Image(systemName: bluetoothManager.isRingingLeft ? "speaker.wave.3.fill" : "speaker.wave.2")
                            Text(bluetoothManager.isRingingLeft ? "Stop Left" : "Ring Left")
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        bluetoothManager.ringBud(isLeft: false, ring: !bluetoothManager.isRingingRight)
                    }) {
                        HStack {
                            Image(systemName: bluetoothManager.isRingingRight ? "speaker.wave.3.fill" : "speaker.wave.2")
                            Text(bluetoothManager.isRingingRight ? "Stop Right" : "Ring Right")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("Plays a high-frequency sound to help locate misplaced earbuds nearby.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("lowBatteryAlerts") private var lowBatteryAlerts = true
    
    var body: some View {
        Form {
            Section(header: Text("Startup")) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            
            Section(header: Text("Notifications")) {
                Toggle("Low battery notifications", isOn: $lowBatteryAlerts)
            }
            
            Section(header: Text("Device Status")) {
                HStack {
                    Text("Device Name")
                    Spacer()
                    Text(bluetoothManager.earbuds.name)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Connection Status")
                    Spacer()
                    Text(bluetoothManager.earbuds.connectionState.rawValue)
                        .foregroundColor(bluetoothManager.earbuds.connectionState == .connected ? .green : .secondary)
                }
                
                if let lastSeen = bluetoothManager.earbuds.lastSeen {
                    HStack {
                        Text("Last Telemetry")
                        Spacer()
                        Text(lastSeen.formatted(date: .omitted, time: .standard))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}
