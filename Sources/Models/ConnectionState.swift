import Foundation

public enum ConnectionState: String, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case unsupported = "Unsupported"
}
