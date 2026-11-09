import CSensors
import Foundation
import StatsKit

// Command-line probe for the sensor readers.
//   statsprobe          print two snapshots, 2 seconds apart
//   statsprobe --raw    dump every HID temperature sensor and SMC fan/temperature key

func dumpRaw() {
    var readings = [cs_temp_reading](repeating: cs_temp_reading(), count: 256)
    let count = cs_hid_temperatures(nil, 0, 0, &readings, Int32(readings.count))
    print("HID temperature sensors: \(count)")
    for reading in readings.prefix(Int(max(count, 0))) {
        var r = reading
        let name = withUnsafePointer(to: &r.name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        print(String(format: "  %-28@ %6.1f C", name as NSString, r.celsius))
    }

    let keyCount = cs_smc_key_count()
    print("SMC keys: \(keyCount)")
    var key = [CChar](repeating: 0, count: 5)
    var type = [CChar](repeating: 0, count: 5)
    for i in 0..<max(keyCount, 0) {
        guard cs_smc_key_at(Int32(i), &key, &type) == 0 else { continue }
        let name = String(cString: key)
        guard name.hasPrefix("F") || name.hasPrefix("T") else { continue }
        var value = 0.0
        if cs_smc_read_double(name, &value) == 0 {
            print(String(format: "  %@ [%@] %.2f", name, String(cString: type), value))
        }
    }
}

if CommandLine.arguments.contains("--raw") {
    dumpRaw()
} else {
    let sampler = SystemSampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 2)
    print(sampler.sample().debugDescription)
}
