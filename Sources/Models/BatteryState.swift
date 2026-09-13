import Foundation

public struct BatteryState: Equatable {
    public var leftPercentage: Int?
    public var rightPercentage: Int?
    public var casePercentage: Int?
    
    public var isLeftCharging: Bool = false
    public var isRightCharging: Bool = false
    public var isCaseCharging: Bool = false
    
    public init(leftPercentage: Int? = nil, rightPercentage: Int? = nil, casePercentage: Int? = nil) {
        self.leftPercentage = leftPercentage
        self.rightPercentage = rightPercentage
        self.casePercentage = casePercentage
    }
}
