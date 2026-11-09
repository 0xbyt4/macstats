import Foundation

public struct ClusterUsage: Sendable, Hashable {
    public let name: String
    /// Logical CPU ids of the cores in this cluster (indexes into `CPUStats.perCore`).
    public let cores: [Int]
    public var coreCount: Int { cores.count }
    /// 0...1
    public let usage: Double
}

public struct CPUStats: Sendable {
    /// 0...1
    public let total: Double
    /// 0...1 per logical core, in logical CPU id order.
    public let perCore: [Double]
    public let clusters: [ClusterUsage]
    public let loadAverage: (Double, Double, Double)
}

public struct GPUStats: Sendable {
    /// 0...1
    public let device: Double
    public let renderer: Double
    public let tiler: Double
    public let memoryInUse: UInt64
    public let coreCount: Int?
}

public enum MemoryPressure: String, Sendable {
    case normal, warning, critical, unknown
}

public struct MemoryStats: Sendable {
    public let total: UInt64
    public let used: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let swapUsed: UInt64
    public let pressure: MemoryPressure
}

public struct BatteryStats: Sendable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let isFullyCharged: Bool
    public let cycleCount: Int
    public let healthPercent: Int
    /// Positive while charging, negative while discharging.
    public let batteryWatts: Double
    /// Minutes, nil when macOS does not know it yet.
    public let minutesRemaining: Int?
    public let temperature: Double?
}

public struct PowerStats: Sendable {
    /// Power the whole system uses right now, in watts.
    public let systemWatts: Double?
    public let adapterName: String?
    public let adapterWatts: Int?
    public let battery: BatteryStats?
}

public struct TemperatureStats: Sendable {
    public let cpuAverage: Double?
    public let cpuMax: Double?
    public let gpuAverage: Double?
    public let gpuMax: Double?
    public let ssd: Double?
    public let battery: Double?
}

public struct FanStats: Sendable, Hashable {
    public let index: Int
    public let rpm: Double
    public let minRPM: Double
    public let maxRPM: Double
}

public enum ThermalPressure: String, Sendable {
    case nominal, fair, serious, critical
}

public struct DiskStats: Sendable {
    public let total: UInt64
    public let available: UInt64
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double
}

public struct NetworkStats: Sendable {
    public let downBytesPerSecond: Double
    public let upBytesPerSecond: Double
}

public struct Snapshot: Sendable {
    public let date: Date
    public let cpu: CPUStats?
    public let gpu: GPUStats?
    public let memory: MemoryStats?
    public let power: PowerStats?
    public let temperatures: TemperatureStats
    public let fans: [FanStats]
    public let thermal: ThermalPressure
    public let disk: DiskStats?
    public let network: NetworkStats?
}

extension Snapshot: CustomDebugStringConvertible {
    public var debugDescription: String {
        func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
        func deg(_ v: Double?) -> String { v.map { String(format: "%.1f C", $0) } ?? "-" }
        func gb(_ v: UInt64) -> String { String(format: "%.1f GB", Double(v) / 1_073_741_824) }
        func rate(_ v: Double) -> String { Format.rate(v) }

        var lines: [String] = []
        if let cpu {
            let clusters = cpu.clusters.map { "\($0.name)(\($0.coreCount)) \(pct($0.usage))" }.joined(separator: ", ")
            lines.append("CPU      total \(pct(cpu.total)) | \(clusters)")
            lines.append("         cores \(cpu.perCore.map(pct).joined(separator: " "))")
            lines.append(String(format: "         load %.2f %.2f %.2f", cpu.loadAverage.0, cpu.loadAverage.1, cpu.loadAverage.2))
        } else {
            lines.append("CPU      -")
        }
        if let gpu {
            lines.append("GPU      device \(pct(gpu.device)) renderer \(pct(gpu.renderer)) tiler \(pct(gpu.tiler)) mem \(gb(gpu.memoryInUse)) cores \(gpu.coreCount.map(String.init) ?? "-")")
        } else {
            lines.append("GPU      -")
        }
        if let m = memory {
            lines.append("Memory   used \(gb(m.used)) / \(gb(m.total)) (app \(gb(m.app)), wired \(gb(m.wired)), compressed \(gb(m.compressed)), cached \(gb(m.cached))) swap \(gb(m.swapUsed)) pressure \(m.pressure.rawValue)")
        } else {
            lines.append("Memory   -")
        }
        let t = temperatures
        lines.append("Temp     CPU avg \(deg(t.cpuAverage)) max \(deg(t.cpuMax)) | GPU avg \(deg(t.gpuAverage)) max \(deg(t.gpuMax)) | SSD \(deg(t.ssd)) | battery \(deg(t.battery))")
        lines.append("Fans     " + (fans.isEmpty ? "-" : fans.map { String(format: "#%d %.0f rpm (%.0f-%.0f)", $0.index, $0.rpm, $0.minRPM, $0.maxRPM) }.joined(separator: ", ")))
        lines.append("Thermal  \(thermal.rawValue)")
        if let p = power {
            var s = "Power    system \(p.systemWatts.map { String(format: "%.1f W", $0) } ?? "-")"
            if let name = p.adapterName { s += " | adapter \(name)" }
            if let b = p.battery {
                s += " | battery \(b.percent)% charging=\(b.isCharging) plugged=\(b.isPluggedIn) \(String(format: "%+.1f W", b.batteryWatts)) cycles \(b.cycleCount) health \(b.healthPercent)% remaining \(b.minutesRemaining.map { "\($0) min" } ?? "-")"
            }
            lines.append(s)
        } else {
            lines.append("Power    -")
        }
        if let d = disk {
            lines.append("Disk     free \(gb(d.available)) / \(gb(d.total)) read \(rate(d.readBytesPerSecond)) write \(rate(d.writeBytesPerSecond))")
        } else {
            lines.append("Disk     -")
        }
        if let n = network {
            lines.append("Network  down \(rate(n.downBytesPerSecond)) up \(rate(n.upBytesPerSecond))")
        } else {
            lines.append("Network  -")
        }
        return lines.joined(separator: "\n")
    }
}

public enum Format {
    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    public static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    public static func gigabytes(_ value: UInt64) -> String {
        String(format: "%.1f GB", Double(value) / 1_073_741_824)
    }
}
