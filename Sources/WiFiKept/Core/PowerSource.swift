import Foundation
import IOKit.ps

enum PowerSource {
    /// True when the Mac is currently running on battery power.
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
