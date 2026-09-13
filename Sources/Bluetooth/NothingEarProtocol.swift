import Foundation
import CoreBluetooth

public class NothingEarProtocol {
    public static let fastPairServiceUUID = CBUUID(string: "FE2C")
    public static let nothingServiceUUID = CBUUID(string: "66666666-6666-6666-6666-666666666666")
    public static let nothingCustomCharUUID = CBUUID(string: "77777777-7777-7777-7777-777777777777")
    
    public static func parseFastPairBatteryData(_ data: Data) -> BatteryState? {
        let bytes = [UInt8](data)
        // Fast Pair battery packet often starts with 0x33
        if bytes.count >= 5 && bytes[0] == 0x33 {
            var state = BatteryState()
            
            let isLeftCharging = (bytes[1] & 0x1) != 0
            let isRightCharging = (bytes[1] & 0x2) != 0
            let isCaseCharging = (bytes[1] & 0x4) != 0
            
            state.isLeftCharging = isLeftCharging
            state.isRightCharging = isRightCharging
            state.isCaseCharging = isCaseCharging
            
            let left = bytes[2] & 0x7F
            let right = bytes[3] & 0x7F
            let caseBat = bytes[4] & 0x7F
            
            if left != 0x7F { state.leftPercentage = Int(left) }
            if right != 0x7F { state.rightPercentage = Int(right) }
            if caseBat != 0x7F { state.casePercentage = Int(caseBat) }
            
            return state
        }
        return nil
    }
}
