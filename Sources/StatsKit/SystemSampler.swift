import Foundation

/// Collects one snapshot of all values. Rates (CPU, disk, network) are the change since the previous call,
/// so call `sample()` at a fixed interval and ignore the first result.
/// Not thread-safe: call it from one thread only.
public final class SystemSampler {
    private let cpu = CPUSampler()
    private let gpu = GPUSampler()
    private let memory = MemorySampler()
    private let power = PowerSampler()
    private let sensors = SensorSampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()

    public init() {}

    public func sample() -> Snapshot {
        let temperatures = sensors.temperatures()
        return Snapshot(
            date: Date(),
            cpu: cpu.sample(),
            gpu: gpu.sample(),
            memory: memory.sample(),
            power: power.sample(batteryTemperature: temperatures.battery),
            temperatures: temperatures,
            fans: sensors.fans(),
            thermal: Self.thermalPressure(),
            disk: disk.sample(),
            network: network.sample()
        )
    }

    private static func thermalPressure() -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
