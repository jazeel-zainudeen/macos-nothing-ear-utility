import Foundation

public struct Earbuds: Equatable {
    public var name: String
    public var batteryState: BatteryState
    public var connectionState: ConnectionState
    public var lastSeen: Date?
    
    public init(name: String, batteryState: BatteryState = BatteryState(), connectionState: ConnectionState = .disconnected, lastSeen: Date? = nil) {
        self.name = name
        self.batteryState = batteryState
        self.connectionState = connectionState
        self.lastSeen = lastSeen
    }
}
