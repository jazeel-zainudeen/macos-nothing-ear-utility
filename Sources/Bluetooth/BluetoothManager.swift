import Foundation
import IOBluetooth
import Combine
import AppKit

public class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published public var earbuds: Earbuds
    @Published public var discoveredServices: [String] = []
    
    private var pollTimer: Timer?
    private var batteryQueryTimer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    
    private var currentDevice: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var isOpeningChannel = false
    private var rxBuffer = [UInt8]()
    
    // Known Nothing device name patterns
    private let nothingNamePatterns = ["Nothing Ear", "Ear (1)", "Ear (2)", "Ear (a)", "Ear (stick)", "Nothing", "CMF"]
    
    public override init() {
        self.earbuds = Earbuds(name: "Nothing Ear", connectionState: .disconnected)
        super.init()
        
        log("[NothingEar] Initializing BluetoothManager...")
        
        // Register for global Bluetooth connect notifications
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        
        // Initial search for paired Nothing devices
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.findAndConnectPairedDevice()
        }
        
        // Poll periodically to ensure connection & RFCOMM channel stay alive
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkConnectionHealth()
        }
    }
    
    deinit {
        pollTimer?.invalidate()
        batteryQueryTimer?.invalidate()
        connectNotification?.unregister()
        disconnectNotification?.unregister()
        _ = rfcommChannel?.close()
    }
    
    // MARK: - Connection Management
    
    private func findAndConnectPairedDevice() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            log("[NothingEar] Failed to get paired devices list")
            return
        }
        
        for device in pairedDevices {
            let name = device.name ?? ""
            if isNothingDevice(name: name) {
                let address = device.addressString ?? ""
                log("[NothingEar] Found paired Nothing device: '\(name)' [\(address)]")
                
                self.currentDevice = device
                DispatchQueue.main.async {
                    self.earbuds.name = name
                }
                
                // Register for disconnect notification
                disconnectNotification?.unregister()
                disconnectNotification = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
                
                // Attempt opening the RFCOMM SPP channel
                openSPPChannel(for: device)
                return
            }
        }
    }
    
    private func checkConnectionHealth() {
        guard let device = currentDevice else {
            findAndConnectPairedDevice()
            return
        }
        
        // If channel is nil or closed, try to open it
        if rfcommChannel == nil && !isOpeningChannel {
            log("[NothingEar] Health check: channel is nil, attempting to connect...")
            openSPPChannel(for: device)
        } else if let channel = rfcommChannel, channel.isOpen() {
            // Channel is healthy, query battery
            sendBatteryQuery()
        }
    }
    
    // MARK: - IOBluetooth Notifications
    
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? ""
        log("[NothingEar] Device connected notification: '\(name)'")
        
        guard isNothingDevice(name: name) else { return }
        
        self.currentDevice = device
        
        disconnectNotification?.unregister()
        disconnectNotification = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        
        DispatchQueue.main.async {
            self.earbuds.name = name
            self.earbuds.connectionState = .connected
            self.earbuds.lastSeen = Date()
            self.updateDiagnostics(device: device)
        }
        
        // Open RFCOMM channel with slight delay to ensure Bluetooth link is stabilized
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.openSPPChannel(for: device)
        }
    }
    
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? ""
        log("[NothingEar] Device disconnected notification: '\(name)'")
        
        guard isNothingDevice(name: name) else { return }
        
        batteryQueryTimer?.invalidate()
        batteryQueryTimer = nil
        
        _ = rfcommChannel?.close()
        rfcommChannel = nil
        isOpeningChannel = false
        rxBuffer.removeAll()
        
        DispatchQueue.main.async {
            self.earbuds.connectionState = .disconnected
            self.earbuds.batteryState = BatteryState()
        }
    }
    
    // MARK: - RFCOMM Channel Management
    
    private func openSPPChannel(for device: IOBluetoothDevice) {
        guard !isOpeningChannel, rfcommChannel == nil else { return }
        
        log("[NothingEar] Attempting to find SPP RFCOMM channel for '\(device.name ?? "")'...")
        
        // 1. Look for known Nothing SPP UUID
        let sppUUIDBytes = stride(from: 0, to: 32, by: 2).map { i -> UInt8 in
            let h = NothingEarProtocol.sppUUIDString.replacingOccurrences(of: "-", with: "")
            let idx = h.index(h.startIndex, offsetBy: i)
            return UInt8(h[idx...h.index(idx, offsetBy: 1)], radix: 16)!
        }
        let sppUUID = IOBluetoothSDPUUID(data: Data(sppUUIDBytes))
        
        var targetChannelID: BluetoothRFCOMMChannelID?
        
        if let rec = device.getServiceRecord(for: sppUUID) {
            var chID: BluetoothRFCOMMChannelID = 0
            if rec.getRFCOMMChannelID(&chID) == kIOReturnSuccess {
                log("[NothingEar] Found SPP service record with RFCOMM channel \(chID)")
                targetChannelID = chID
            }
        }
        
        // 2. Fallback: Search all SDP services for any SPP service record
        if targetChannelID == nil, let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for rec in services {
                var chID: BluetoothRFCOMMChannelID = 0
                if rec.getRFCOMMChannelID(&chID) == kIOReturnSuccess {
                    let serviceName = rec.getServiceName() ?? ""
                    log("[NothingEar] Discovered candidate RFCOMM service: '\(serviceName)' channel \(chID)")
                    if serviceName.localizedCaseInsensitiveContains("spp") || chID == 15 {
                        targetChannelID = chID
                        break
                    }
                }
            }
        }
        
        guard let channelID = targetChannelID else {
            log("[NothingEar] SPP channel not found in SDP cache, initiating SDP query...")
            device.performSDPQuery(nil)
            return
        }
        
        isOpeningChannel = true
        var ch: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        log("[NothingEar] openRFCOMMChannelAsync (ch \(channelID)) result: \(result)")
        
        if result == kIOReturnSuccess {
            self.rfcommChannel = ch
        } else {
            isOpeningChannel = false
            self.rfcommChannel = nil
        }
    }
    
    public func sendBatteryQuery() {
        guard let channel = rfcommChannel, channel.isOpen() else {
            log("[NothingEar] Cannot send battery query: channel not open")
            return
        }
        
        var frame = NothingEarProtocol.createReadBatteryFrame()
        let res = channel.writeSync(&frame, length: UInt16(frame.count))
        log("[NothingEar] Battery query sent (writeSync result: \(res))")
    }
    
    // MARK: - IOBluetoothRFCOMMChannelDelegate
    
    public func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        isOpeningChannel = false
        log("[NothingEar] rfcommChannelOpenComplete status: \(status)")
        
        if status == kIOReturnSuccess {
            self.rfcommChannel = ch
            
            DispatchQueue.main.async {
                self.earbuds.connectionState = .connected
                self.earbuds.lastSeen = Date()
                if let dev = self.currentDevice {
                    self.updateDiagnostics(device: dev)
                }
            }
            
            // Query battery immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.sendBatteryQuery()
            }
            
            // Periodically refresh battery status every 5 seconds so box open/close is detected quickly
            batteryQueryTimer?.invalidate()
            batteryQueryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendBatteryQuery()
            }
        } else {
            self.rfcommChannel = nil
        }
    }
    
    public func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        let buffer = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        rxBuffer.append(contentsOf: buffer)
        
        let frames = NothingEarProtocol.extractFrames(from: &rxBuffer)
        for frame in frames {
            log("[NothingEar] Received frame cmd=0x\(String(frame.command, radix: 16)) payloadLen=\(frame.payload.count)")
            
            if frame.command == NothingEarProtocol.Command.respBattery || frame.command == NothingEarProtocol.Command.pushBattery {
                if let newBattery = NothingEarProtocol.parseBatteryPayload(frame.payload) {
                    log("[NothingEar] Battery parsed: L=\(String(describing: newBattery.leftPercentage))%(chg=\(newBattery.isLeftCharging)) R=\(String(describing: newBattery.rightPercentage))%(chg=\(newBattery.isRightCharging)) Case=\(String(describing: newBattery.casePercentage))%(chg=\(newBattery.isCaseCharging))")
                    DispatchQueue.main.async {
                        var updated = self.earbuds.batteryState
                        
                        // When an earbud is kept inside the closed case, it powers down its link
                        // and the device omits it from the battery packet. Update directly so nil is reflected.
                        updated.leftPercentage = newBattery.leftPercentage
                        updated.isLeftCharging = newBattery.isLeftCharging
                        
                        updated.rightPercentage = newBattery.rightPercentage
                        updated.isRightCharging = newBattery.isRightCharging
                        
                        // When box is open, casePercentage is present.
                        // When box is closed, casePercentage is nil.
                        let wasOpen = updated.isCaseOpen
                        updated.casePercentage = newBattery.casePercentage
                        updated.isCaseCharging = newBattery.isCaseCharging
                        if updated.isCaseOpen != wasOpen {
                            self.log("[NothingEar] Case lid state changed: \(updated.isCaseOpen ? "OPENED" : "CLOSED")")
                        }
                        
                        self.earbuds.batteryState = updated
                        self.earbuds.connectionState = .connected
                        self.earbuds.lastSeen = Date()
                    }
                }
            }
        }
    }
    
    public func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        log("[NothingEar] rfcommChannelClosed")
        rfcommChannel = nil
        isOpeningChannel = false
        batteryQueryTimer?.invalidate()
        batteryQueryTimer = nil
        rxBuffer.removeAll()
    }
    
    // MARK: - Utilities
    
    private func isNothingDevice(name: String) -> Bool {
        return nothingNamePatterns.contains { name.localizedCaseInsensitiveContains($0) }
    }
    
    private func updateDiagnostics(device: IOBluetoothDevice) {
        var info: [String] = []
        info.append("Device: \(device.name ?? "Unknown")")
        info.append("Address: \(device.addressString ?? "Unknown")")
        info.append("RFCOMM Connected: \(rfcommChannel?.isOpen() ?? false)")
        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            info.append("SDP Services Count: \(services.count)")
            for (idx, service) in services.enumerated() {
                var chID: BluetoothRFCOMMChannelID = 0
                if service.getRFCOMMChannelID(&chID) == kIOReturnSuccess {
                    info.append("  [\(idx)] \(service.getServiceName() ?? "Service") (RFCOMM Ch: \(chID))")
                }
            }
        }
        DispatchQueue.main.async {
            self.discoveredServices = info
        }
    }
    
    private func log(_ message: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        print(line, terminator: "")
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NothingEarUtility.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Menu Bar Image Generation
extension BluetoothManager {
    public var menuBarImage: NSImage {
        guard earbuds.connectionState == .connected else {
            let fallback = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Nothing Ear") ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }
        return generateMenuBarImage(state: earbuds.batteryState)
    }
    
    private func generateMenuBarImage(state: BatteryState) -> NSImage {
        let leftPct = state.leftPercentage
        let isLeftCharging = state.isLeftCharging
        let rightPct = state.rightPercentage
        let isRightCharging = state.isRightCharging
        let casePct = state.casePercentage
        let isCaseCharging = state.isCaseCharging
        
        if leftPct == nil && rightPct == nil && casePct == nil && !isLeftCharging && !isRightCharging && !isCaseCharging {
            let fallback = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Nothing Ear") ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }
        
        let fontConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let boltConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        
        func batterySymbol(for p: Int) -> String {
            switch p {
            case 90...100: return "battery.100"
            case 65..<90: return "battery.75"
            case 35..<65: return "battery.50"
            case 10..<35: return "battery.25"
            default: return "battery.0"
            }
        }
        
        struct DrawItem {
            let image: NSImage
            let opacity: CGFloat
        }
        
        var groups: [[DrawItem]] = []
        
        // Group 1: Left earbud
        var leftGroup: [DrawItem] = []
        if let img = NSImage(systemSymbolName: "earbud.left", accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
            leftGroup.append(DrawItem(image: img, opacity: leftPct != nil ? 1.0 : 0.35))
        }
        if isLeftCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(boltConfig) {
            leftGroup.append(DrawItem(image: bolt, opacity: 1.0))
        }
        if let l = leftPct, let bImg = NSImage(systemSymbolName: batterySymbol(for: l), accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
            leftGroup.append(DrawItem(image: bImg, opacity: 1.0))
        }
        groups.append(leftGroup)
        
        // Group 2: Right earbud
        var rightGroup: [DrawItem] = []
        if let img = NSImage(systemSymbolName: "earbud.right", accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
            rightGroup.append(DrawItem(image: img, opacity: rightPct != nil ? 1.0 : 0.35))
        }
        if isRightCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(boltConfig) {
            rightGroup.append(DrawItem(image: bolt, opacity: 1.0))
        }
        if let r = rightPct, let bImg = NSImage(systemSymbolName: batterySymbol(for: r), accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
            rightGroup.append(DrawItem(image: bImg, opacity: 1.0))
        }
        groups.append(rightGroup)
        
        // Group 3: Case (shown if open or charging)
        if casePct != nil || isCaseCharging {
            var caseGroup: [DrawItem] = []
            if let caseImg = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
                caseGroup.append(DrawItem(image: caseImg, opacity: 1.0))
            }
            if isCaseCharging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(boltConfig) {
                caseGroup.append(DrawItem(image: bolt, opacity: 1.0))
            }
            if let c = casePct, let bImg = NSImage(systemSymbolName: batterySymbol(for: c), accessibilityDescription: nil)?.withSymbolConfiguration(fontConfig) {
                caseGroup.append(DrawItem(image: bImg, opacity: 1.0))
            }
            groups.append(caseGroup)
        }
        
        let innerSpacing: CGFloat = 2.0
        let groupSpacing: CGFloat = 6.0
        
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 16.0
        
        for (gIdx, group) in groups.enumerated() {
            for (iIdx, item) in group.enumerated() {
                totalWidth += item.image.size.width
                maxHeight = max(maxHeight, item.image.size.height)
                if iIdx < group.count - 1 {
                    totalWidth += innerSpacing
                }
            }
            if gIdx < groups.count - 1 {
                totalWidth += groupSpacing
            }
        }
        
        let finalSize = NSSize(width: max(16.0, ceil(totalWidth)), height: ceil(maxHeight))
        let result = NSImage(size: finalSize, flipped: false) { rect in
            var currentX: CGFloat = 0
            for (gIdx, group) in groups.enumerated() {
                for (iIdx, item) in group.enumerated() {
                    let y = (rect.height - item.image.size.height) / 2.0
                    let targetRect = NSRect(x: currentX, y: y, width: item.image.size.width, height: item.image.size.height)
                    item.image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: item.opacity)
                    currentX += item.image.size.width
                    if iIdx < group.count - 1 {
                        currentX += innerSpacing
                    }
                }
                if gIdx < groups.count - 1 {
                    currentX += groupSpacing
                }
            }
            return true
        }
        result.isTemplate = true
        return result
    }
}
