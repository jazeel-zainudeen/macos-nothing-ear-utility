import Foundation

public struct NothingEarProtocol {
    public static let sppUUIDString = "aeac4a03-dff5-498f-843a-34487cf133eb"
    public static let fastPairUUIDString = "df21fe2c-2515-4fdb-8886-f12c4d67927c"
    
    public static let header: [UInt8] = [0x55, 0x60, 0x01]
    
    public enum Command {
        public static let readBattery: UInt16   = 0xC007
        public static let respBattery: UInt16   = 0x4007
        public static let pushBattery: UInt16   = 0xE001
        
        public static let readANC: UInt16       = 0xC01E
        public static let respANC: UInt16       = 0x401E
        
        public static let readInEar: UInt16     = 0xC00E
        public static let respInEar: UInt16     = 0x400E
    }
    
    public struct Frame: Equatable {
        public let command: UInt16
        public let operationID: UInt8
        public let payload: [UInt8]
        
        public init(command: UInt16, operationID: UInt8, payload: [UInt8]) {
            self.command = command
            self.operationID = operationID
            self.payload = payload
        }
    }
    
    /// CRC16-Modbus: poly 0xA001, initial value 0xFFFF
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc = crc >> 1
                }
            }
        }
        return crc
    }
    
    /// Encodes a request frame into bytes ready to send over RFCOMM
    public static func encode(command: UInt16, operationID: UInt8 = 1, payload: [UInt8] = []) -> [UInt8] {
        var bytes = header
        bytes.append(UInt8(command & 0xFF))
        bytes.append(UInt8((command >> 8) & 0xFF))
        bytes.append(UInt8(payload.count))
        bytes.append(0x00) // Reserved
        bytes.append(operationID)
        bytes.append(contentsOf: payload)
        
        let checksum = crc16(bytes)
        bytes.append(UInt8(checksum & 0xFF))
        bytes.append(UInt8((checksum >> 8) & 0xFF))
        return bytes
    }
    
    public static func createReadBatteryFrame(operationID: UInt8 = 1) -> [UInt8] {
        return encode(command: Command.readBattery, operationID: operationID)
    }
    
    /// Extracts complete frames from the incoming RFCOMM byte stream buffer
    public static func extractFrames(from buffer: inout [UInt8]) -> [Frame] {
        var frames = [Frame]()
        
        while buffer.count >= 8 {
            // Find header prefix 0x55, 0x60, 0x01
            guard buffer[0] == header[0], buffer[1] == header[1], buffer[2] == header[2] else {
                buffer.removeFirst()
                continue
            }
            
            let payloadLen = Int(buffer[5])
            let totalLength = 8 + payloadLen + 2 // header(8) + payload + crc(2)
            
            guard buffer.count >= totalLength else {
                // Wait for more data to arrive
                break
            }
            
            let frameBytes = Array(buffer.prefix(totalLength))
            buffer.removeFirst(totalLength)
            
            let bodyBytes = Array(frameBytes.prefix(8 + payloadLen))
            let expectedCRC = crc16(bodyBytes)
            let receivedCRC = UInt16(frameBytes[8 + payloadLen]) | (UInt16(frameBytes[9 + payloadLen]) << 8)
            
            if expectedCRC == receivedCRC {
                let cmd = UInt16(frameBytes[3]) | (UInt16(frameBytes[4]) << 8)
                let opID = frameBytes[7]
                let payload = Array(frameBytes[8..<(8 + payloadLen)])
                frames.append(Frame(command: cmd, operationID: opID, payload: payload))
            } else {
                print("[NothingEarProtocol] Checksum mismatch: expected 0x\(String(expectedCRC, radix: 16)), received 0x\(String(receivedCRC, radix: 16))")
            }
        }
        
        return frames
    }
    
    /// Parses battery payload received from Nothing Ear
    /// Format: payload[0] = connected devices count
    /// For each device: deviceId (UInt8), rawValue (UInt8)
    /// deviceId: 0x02 = Left, 0x03 = Right, 0x04 = Case
    /// rawValue: lower 7 bits = percentage (0-100), MSB 0x80 = isCharging
    public static func parseBatteryPayload(_ payload: [UInt8]) -> BatteryState? {
        guard !payload.isEmpty else { return nil }
        
        let count = Int(payload[0])
        guard payload.count >= 1 + (count * 2) else { return nil }
        
        var state = BatteryState()
        
        for i in 0..<count {
            let deviceId = payload[1 + (i * 2)]
            let raw = payload[2 + (i * 2)]
            let level = Int(raw & 0x7F)
            let isCharging = (raw & 0x80) != 0
            
            switch deviceId {
            case 0x02: // Left Bud
                state.leftPercentage = level
                state.isLeftCharging = isCharging
            case 0x03: // Right Bud
                state.rightPercentage = level
                state.isRightCharging = isCharging
            case 0x04: // Case
                state.casePercentage = level
                state.isCaseCharging = isCharging
            default:
                break
            }
        }
        
        return state
    }
}
