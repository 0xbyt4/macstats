import CSensors
import Foundation

/// Reads temperatures and fan speeds.
///
/// - CPU and GPU temperatures come from SMC keys that start with "Tp" (CPU) and "Tg" (GPU).
///   Apple does not document these keys; the prefixes follow the convention that
///   open source monitors use on Apple Silicon.
/// - SSD and battery temperatures come from the HID temperature sensors.
///   Each HID read costs about 1 ms, so only one sensor of each kind is read.
/// - Fan speeds come from the SMC keys FNum and F<n>Ac / F<n>Mn / F<n>Mx.
final class SensorSampler {
    private static let validRange = 1.0...130.0
    private static let ssdSensor = "NAND"
    private static let batterySensor = "gas gauge battery"

    private lazy var smcAvailable: Bool = cs_smc_open() == 0
    private lazy var temperatureKeys: [String: [String]] = smcKeys(prefixes: ["Tp", "Tg"])
    private var cpuKeys: [String] { temperatureKeys["Tp", default: []] }
    private var gpuKeys: [String] { temperatureKeys["Tg", default: []] }
    private lazy var fanCount: Int = {
        var value = 0.0
        return smcAvailable && cs_smc_read_double("FNum", &value) == 0 ? Int(value) : 0
    }()

    deinit {
        cs_smc_close()
    }

    func temperatures() -> TemperatureStats {
        let cpu = readValues(cpuKeys)
        let gpu = readValues(gpuKeys)
        let hid = hidTemperatures(prefixes: [Self.ssdSensor, Self.batterySensor])

        return TemperatureStats(
            cpuAverage: average(cpu),
            cpuMax: cpu.max(),
            gpuAverage: average(gpu),
            gpuMax: gpu.max(),
            ssd: hid.first { $0.name.hasPrefix(Self.ssdSensor) }?.celsius,
            battery: hid.first { $0.name.hasPrefix(Self.batterySensor) }?.celsius
        )
    }

    func fans() -> [FanStats] {
        guard smcAvailable else { return [] }
        return (0..<fanCount).compactMap { index in
            guard let rpm = read("F\(index)Ac") else { return nil }
            return FanStats(index: index, rpm: max(0, rpm), minRPM: read("F\(index)Mn") ?? 0, maxRPM: read("F\(index)Mx") ?? 0)
        }
    }

    private func read(_ key: String) -> Double? {
        var value = 0.0
        return cs_smc_read_double(key, &value) == 0 ? value : nil
    }

    private func readValues(_ keys: [String]) -> [Double] {
        keys.compactMap(read).filter { Self.validRange.contains($0) }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Finds the float SMC keys with the given prefixes that return a valid temperature.
    /// The SMC has thousands of keys, so this runs once.
    private func smcKeys(prefixes: [String]) -> [String: [String]] {
        guard smcAvailable else { return [:] }
        let count = cs_smc_key_count()
        guard count > 0 else { return [:] }

        var key = [CChar](repeating: 0, count: 5)
        var type = [CChar](repeating: 0, count: 5)
        var result: [String: [String]] = [:]
        for index in 0..<count {
            guard cs_smc_key_at(index, &key, &type) == 0 else { continue }
            let name = String(cString: key)
            guard let prefix = prefixes.first(where: { name.hasPrefix($0) }),
                  String(cString: type) == "flt " else { continue }
            if let value = read(name), Self.validRange.contains(value) {
                result[prefix, default: []].append(name)
            }
        }
        return result
    }

    /// Reads the first HID temperature sensor for each name prefix.
    private func hidTemperatures(prefixes: [String]) -> [(name: String, celsius: Double)] {
        let cStrings = prefixes.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        let pointers = cStrings.map { UnsafePointer($0) }

        var readings = [cs_temp_reading](repeating: cs_temp_reading(), count: prefixes.count)
        let count = cs_hid_temperatures(pointers, Int32(pointers.count), 1, &readings, Int32(readings.count))
        guard count > 0 else { return [] }
        return readings.prefix(Int(count)).compactMap { reading in
            var copy = reading
            let name = withUnsafePointer(to: &copy.name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
            }
            return Self.validRange.contains(reading.celsius) ? (name, reading.celsius) : nil
        }
    }
}
