import Foundation

/// Reads battery and power data from the AppleSmartBattery service.
final class PowerSampler {
    func sample(batteryTemperature: Double?) -> PowerStats? {
        guard let props = IOKitHelpers.properties(ofClass: "AppleSmartBattery").first else { return nil }

        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let adapter = props["AdapterDetails"] as? [String: Any]
        let pluggedIn = (props["ExternalConnected"] as? Bool) ?? false

        // SystemLoad is the power the whole computer uses, in milliwatts.
        let systemWatts = IOKitHelpers.int(telemetry?["SystemLoad"]).map { Double($0) / 1000 }

        var battery: BatteryStats?
        if let percent = IOKitHelpers.int(props["CurrentCapacity"]) {
            let millivolts = Double(IOKitHelpers.int(props["Voltage"]) ?? 0)
            let milliamps = Double(IOKitHelpers.signedInt(props["Amperage"]) ?? 0)
            let health: Int
            if let max = IOKitHelpers.int(props["MaxCapacity"]), max <= 100 {
                health = max
            } else if let raw = IOKitHelpers.int(props["AppleRawMaxCapacity"]),
                      let design = IOKitHelpers.int(props["DesignCapacity"]), design > 0 {
                health = min(100, raw * 100 / design)
            } else {
                health = 0
            }
            let remaining = IOKitHelpers.int(props["TimeRemaining"]).flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }

            battery = BatteryStats(
                percent: percent,
                isCharging: (props["IsCharging"] as? Bool) ?? false,
                isPluggedIn: pluggedIn,
                isFullyCharged: (props["FullyCharged"] as? Bool) ?? false,
                cycleCount: IOKitHelpers.int(props["CycleCount"]) ?? 0,
                healthPercent: health,
                batteryWatts: millivolts * milliamps / 1_000_000,
                minutesRemaining: remaining,
                temperature: batteryTemperature
            )
        }

        return PowerStats(
            systemWatts: systemWatts,
            adapterName: pluggedIn ? adapter?["Name"] as? String : nil,
            adapterWatts: pluggedIn ? IOKitHelpers.int(adapter?["Watts"]) : nil,
            battery: battery
        )
    }
}
