import Foundation
import IOBluetooth
import Combine
import AppKit

public class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    @Published public var earbuds: Earbuds
    @Published public var discoveredServices: [String] = []
    @Published public var isHovered: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var justRefreshed: Bool = false
    
    private var pollTimer: Timer?
    private var batteryQueryTimer: Timer?
    private var hoverTimer: Timer?
    private weak var statusButton: NSStatusBarButton?
    private var lastValidFrame: NSRect = .zero
    private var hoverEnterCount: Int = 0
    private var hoverExitCount: Int = 0
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
        
        startHoverMonitoring()
        
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
        hoverTimer?.invalidate()
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
            self.updateStatusButtonImage()
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
            self.updateStatusButtonImage()
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
        DispatchQueue.main.async {
            self.isRefreshing = true
        }
        
        guard let channel = rfcommChannel, channel.isOpen() else {
            log("[NothingEar] Cannot send battery query: channel not open")
            if let dev = currentDevice {
                openSPPChannel(for: dev)
            } else {
                findAndConnectPairedDevice()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.isRefreshing = false
            }
            return
        }
        
        var frame = NothingEarProtocol.createReadBatteryFrame()
        let res = channel.writeSync(&frame, length: UInt16(frame.count))
        log("[NothingEar] Battery query sent (writeSync result: \(res))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.isRefreshing == true {
                self?.isRefreshing = false
            }
        }
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
                let hexStr = frame.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                log("[NothingEar] Raw battery payload: [\(hexStr)]")
                if let newBattery = NothingEarProtocol.parseBatteryPayload(frame.payload) {
                    log("[NothingEar] Battery parsed: L=\(String(describing: newBattery.leftPercentage))%(chg=\(newBattery.isLeftCharging)) R=\(String(describing: newBattery.rightPercentage))%(chg=\(newBattery.isRightCharging)) Case=\(String(describing: newBattery.casePercentage))%(chg=\(newBattery.isCaseCharging))")
                    DispatchQueue.main.async {
                        var updated = self.earbuds.batteryState
                        
                        updated.leftPercentage = newBattery.leftPercentage
                        updated.rightPercentage = newBattery.rightPercentage
                        
                        // When box is open, casePercentage is present.
                        // When box is closed, casePercentage is nil.
                        let wasOpen = updated.isCaseOpen
                        updated.casePercentage = newBattery.casePercentage
                        updated.isCaseCharging = newBattery.isCaseCharging
                        if updated.isCaseOpen != wasOpen {
                            self.log("[NothingEar] Case lid state changed: \(updated.isCaseOpen ? "OPENED" : "CLOSED")")
                        }
                        
                        // Bud charging detection:
                        // Earbuds charge whenever they are seated inside the case.
                        // 1) Explicit hardware charging flag (raw & 0x80 != 0)
                        // 2) Bud is inside the case (omitted/nil while connected to case or other bud)
                        if newBattery.isLeftCharging {
                            updated.isLeftCharging = true
                        } else if newBattery.leftPercentage == nil && (newBattery.rightPercentage != nil || newBattery.casePercentage != nil) {
                            updated.isLeftCharging = true
                        } else {
                            updated.isLeftCharging = false
                        }
                        
                        if newBattery.isRightCharging {
                            updated.isRightCharging = true
                        } else if newBattery.rightPercentage == nil && (newBattery.leftPercentage != nil || newBattery.casePercentage != nil) {
                            updated.isRightCharging = true
                        } else {
                            updated.isRightCharging = false
                        }
                        
                        self.earbuds.batteryState = updated
                        self.earbuds.connectionState = .connected
                        self.earbuds.lastSeen = Date()
                        self.isRefreshing = false
                        self.justRefreshed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.justRefreshed = false
                        }
                        self.updateStatusButtonImage()
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
    
    public func menuBarImage(showBattery: Bool = false) -> NSImage {
        return menuBarImage
    }
    
    private func chargeColor(for percent: Int?) -> NSColor {
        guard let p = percent else {
            return NSColor.secondaryLabelColor.withAlphaComponent(0.4)
        }
        switch p {
        case 60...100:
            return NSColor.systemGreen
        case 30..<60:
            return NSColor.systemYellow
        default:
            return NSColor.systemRed
        }
    }
    
    private func generateMenuBarImage(state: BatteryState) -> NSImage {
        let leftPct = state.leftPercentage
        let isLeftCharging = state.isLeftCharging
        let rightPct = state.rightPercentage
        let isRightCharging = state.isRightCharging
        let casePct = state.casePercentage
        let isCaseCharging = state.isCaseCharging
        
        if leftPct == nil && rightPct == nil && casePct == nil {
            let fallback = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Nothing Ear") ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }
        
        let fontConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let budConfig = fontConfig.applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.headerTextColor]))
        
        let dotSize: CGFloat = 4.0
        let dotOverlap: CGFloat = 1.5
        let extraDotW = max(0, dotSize - dotOverlap)
        let pairSpacing: CGFloat = 2.0
        
        struct DeviceUnit {
            let icon: NSImage
            let opacity: CGFloat
            let dotColor: NSColor?
        }
        
        var units: [DeviceUnit] = []
        
        // Unit 1: Left earbud
        if let img = NSImage(systemSymbolName: "earbud.left", accessibilityDescription: "Left Earbud")?.withSymbolConfiguration(budConfig) {
            units.append(DeviceUnit(
                icon: img,
                opacity: leftPct != nil ? 1.0 : 0.35,
                dotColor: leftPct != nil ? chargeColor(for: leftPct) : nil
            ))
        }
        
        // Unit 2: Right earbud
        if let img = NSImage(systemSymbolName: "earbud.right", accessibilityDescription: "Right Earbud")?.withSymbolConfiguration(budConfig) {
            units.append(DeviceUnit(
                icon: img,
                opacity: rightPct != nil ? 1.0 : 0.35,
                dotColor: rightPct != nil ? chargeColor(for: rightPct) : nil
            ))
        }
        
        // Unit 3: Case (shown if casePct != nil)
        if let cPct = casePct {
            if let caseImg = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Case")?.withSymbolConfiguration(budConfig) {
                units.append(DeviceUnit(
                    icon: caseImg,
                    opacity: 1.0,
                    dotColor: chargeColor(for: cPct)
                ))
            }
        }
        
        // Calculate total width
        var totalWidth: CGFloat = 0
        for (idx, u) in units.enumerated() {
            totalWidth += u.icon.size.width + (u.dotColor != nil ? extraDotW : 0)
            if idx < units.count - 1 {
                totalWidth += (idx == 0 ? pairSpacing : 4.0)
            }
        }
        
        let finalSize = NSSize(width: max(16.0, ceil(totalWidth)), height: 16.0)
        let result = NSImage(size: finalSize, flipped: false) { rect in
            var curX: CGFloat = 0
            for (idx, u) in units.enumerated() {
                // Draw uncolored bud icon
                let yIcon = (rect.height - u.icon.size.height) / 2.0
                let iconRect = NSRect(x: curX, y: yIcon, width: u.icon.size.width, height: u.icon.size.height)
                u.icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: u.opacity)
                
                // Draw small colored charge indicator dot at top-right of device
                if let dotCol = u.dotColor {
                    let dotX = curX + u.icon.size.width - dotOverlap
                    let dotY = rect.height - dotSize - 1.0
                    let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                    
                    // Subtle background cutout for clear contrast
                    NSColor.black.withAlphaComponent(0.4).setFill()
                    NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.5, dy: -0.5)).fill()
                    
                    dotCol.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                }
                
                curX += u.icon.size.width + (u.dotColor != nil ? extraDotW : 0)
                
                if idx < units.count - 1 {
                    curX += (idx == 0 ? pairSpacing : 4.0)
                }
            }
            return true
        }
        result.isTemplate = false
        return result
    }
}

// MARK: - Menu Bar Status Item Management
extension BluetoothManager {
    public func startHoverMonitoring() {
        // Battery level icons on hover have been replaced with charge status colors.
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
    
    private func findStatusButton() -> NSStatusBarButton? {
        for w in NSApp.windows {
            if NSStringFromClass(type(of: w)).contains("NSStatusBarWindow") {
                func search(in view: NSView) -> NSStatusBarButton? {
                    if let btn = view as? NSStatusBarButton { return btn }
                    for sub in view.subviews {
                        if let btn = search(in: sub) { return btn }
                    }
                    return nil
                }
                if let cv = w.contentView, let btn = search(in: cv) {
                    return btn
                }
            }
        }
        return nil
    }
    
    public func updateStatusButtonImage() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.statusButton == nil {
                self.statusButton = self.findStatusButton()
                self.statusButton?.toolTip = "Nothing Ear"
            }
            if let btn = self.statusButton {
                btn.image = self.menuBarImage
            }
        }
    }
}

