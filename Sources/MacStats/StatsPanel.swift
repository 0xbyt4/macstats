import AppKit
import StatsKit
import SwiftUI

struct StatsPanel: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    CPUSection(cpu: snapshot.cpu)
                    GPUSection(gpu: snapshot.gpu)
                    MemorySection(memory: snapshot.memory)
                    TemperatureSection(temperatures: snapshot.temperatures, thermal: snapshot.thermal, fans: snapshot.fans)
                    PowerSection(power: snapshot.power)
                    DiskNetworkSection(disk: snapshot.disk, network: snapshot.network)
                }
                .padding(14)
            } else {
                ProgressView("Reading sensors…")
                    .frame(maxWidth: .infinity)
                    .padding(30)
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var footer: some View {
        HStack {
            Text("Updates every 2 s")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Sections

private struct CPUSection: View {
    let cpu: CPUStats?

    var body: some View {
        StatSection(title: "CPU", systemImage: "cpu", headline: cpu.map { percent($0.total) }) {
            if let cpu {
                UsageBar(value: cpu.total)
                ForEach(cpu.clusters, id: \.name) { cluster in
                    ValueRow(label: "\(cluster.name) cores (\(cluster.coreCount))", value: percent(cluster.usage))
                }
                CoreBars(cpu: cpu)
                ValueRow(label: "Load average",
                         value: String(format: "%.2f  %.2f  %.2f", cpu.loadAverage.0, cpu.loadAverage.1, cpu.loadAverage.2))
            } else {
                Unavailable()
            }
        }
    }
}

private struct GPUSection: View {
    let gpu: GPUStats?

    var body: some View {
        StatSection(title: gpu?.coreCount.map { "GPU (\($0) cores)" } ?? "GPU", systemImage: "square.stack.3d.up",
                    headline: gpu.map { percent($0.device) }) {
            if let gpu {
                UsageBar(value: gpu.device)
                ValueRow(label: "Renderer", value: percent(gpu.renderer))
                ValueRow(label: "Tiler", value: percent(gpu.tiler))
                ValueRow(label: "GPU memory in use", value: Format.gigabytes(gpu.memoryInUse))
            } else {
                Unavailable()
            }
        }
    }
}

private struct MemorySection: View {
    let memory: MemoryStats?

    var body: some View {
        StatSection(title: "Memory", systemImage: "memorychip",
                    headline: memory.map { "\(Format.gigabytes($0.used)) / \(Format.gigabytes($0.total))" }) {
            if let memory {
                UsageBar(value: Double(memory.used) / Double(max(memory.total, 1)))
                ValueRow(label: "Pressure", value: memory.pressure.rawValue.capitalized, color: pressureColor(memory.pressure))
                ValueRow(label: "App memory", value: Format.gigabytes(memory.app))
                ValueRow(label: "Wired", value: Format.gigabytes(memory.wired))
                ValueRow(label: "Compressed", value: Format.gigabytes(memory.compressed))
                ValueRow(label: "Cached files", value: Format.gigabytes(memory.cached))
                ValueRow(label: "Swap used", value: Format.gigabytes(memory.swapUsed))
            } else {
                Unavailable()
            }
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color? {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: nil
        }
    }
}

private struct TemperatureSection: View {
    let temperatures: TemperatureStats
    let thermal: ThermalPressure
    let fans: [FanStats]

    var body: some View {
        StatSection(title: "Temperature", systemImage: "thermometer.medium", headline: thermal.rawValue.capitalized,
                    headlineColor: thermalColor) {
            TemperatureRow(label: "CPU (avg / max)", average: temperatures.cpuAverage, maximum: temperatures.cpuMax)
            TemperatureRow(label: "GPU (avg / max)", average: temperatures.gpuAverage, maximum: temperatures.gpuMax)
            TemperatureRow(label: "SSD", average: temperatures.ssd)
            TemperatureRow(label: "Battery", average: temperatures.battery)
            ForEach(fans, id: \.index) { fan in
                ValueRow(label: "Fan \(fan.index + 1)",
                         value: fan.rpm < 1 ? "Stopped" : String(format: "%.0f rpm (%.0f%%)", fan.rpm, fanPercent(fan) * 100))
            }
        }
    }

    private var thermalColor: Color {
        switch thermal {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }

    private func fanPercent(_ fan: FanStats) -> Double {
        fan.maxRPM > 0 ? min(1, fan.rpm / fan.maxRPM) : 0
    }
}

private struct PowerSection: View {
    let power: PowerStats?

    var body: some View {
        StatSection(title: "Power", systemImage: "bolt", headline: power?.systemWatts.map { String(format: "%.1f W", $0) }) {
            if let power {
                if let battery = power.battery {
                    UsageBar(value: Double(battery.percent) / 100, colorByLevel: false)
                    ValueRow(label: "Battery", value: "\(battery.percent)%  \(state(battery))")
                    ValueRow(label: battery.batteryWatts >= 0 ? "Charging power" : "Battery drain",
                             value: String(format: "%.1f W", abs(battery.batteryWatts)))
                    if let minutes = battery.minutesRemaining, !battery.isFullyCharged {
                        ValueRow(label: battery.isCharging ? "Time to full" : "Time left",
                                 value: String(format: "%d:%02d", minutes / 60, minutes % 60))
                    }
                    ValueRow(label: "Health / cycles", value: "\(battery.healthPercent)%  /  \(battery.cycleCount)")
                }
                if let adapter = power.adapterName {
                    ValueRow(label: "Adapter", value: adapter)
                }
            } else {
                Unavailable()
            }
        }
    }

    private func state(_ battery: BatteryStats) -> String {
        if battery.isFullyCharged { return "Full" }
        if battery.isCharging { return "Charging" }
        return battery.isPluggedIn ? "Plugged in, not charging" : "On battery"
    }
}

private struct DiskNetworkSection: View {
    let disk: DiskStats?
    let network: NetworkStats?

    var body: some View {
        StatSection(title: "Disk & Network", systemImage: "internaldrive",
                    headline: disk.map { "\(Format.gigabytes($0.available)) free" }) {
            if let disk {
                UsageBar(value: 1 - Double(disk.available) / Double(max(disk.total, 1)))
                ValueRow(label: "Disk read / write",
                         value: "\(Format.rate(disk.readBytesPerSecond))  /  \(Format.rate(disk.writeBytesPerSecond))")
            }
            if let network {
                ValueRow(label: "Network down / up",
                         value: "\(Format.rate(network.downBytesPerSecond))  /  \(Format.rate(network.upBytesPerSecond))")
            }
            if disk == nil && network == nil {
                Unavailable()
            }
        }
    }
}

// MARK: - Building blocks

private struct StatSection<Content: View>: View {
    let title: String
    let systemImage: String
    var headline: String?
    var headlineColor: Color?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let headline {
                    Text(headline)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(headlineColor ?? .primary)
                }
            }
            content
        }
    }
}

private struct ValueRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
        .font(.callout)
    }
}

private struct TemperatureRow: View {
    let label: String
    let average: Double?
    var maximum: Double?

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let average {
                Text(celsius(average)).foregroundStyle(temperatureColor(average))
                if let maximum {
                    Text("/").foregroundStyle(.secondary)
                    Text(celsius(maximum)).foregroundStyle(temperatureColor(maximum))
                }
            } else {
                Text("–").foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
    }

    private func celsius(_ value: Double) -> String {
        String(format: "%.0f °C", value)
    }

    private func temperatureColor(_ value: Double) -> Color {
        switch value {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }
}

private struct UsageBar: View {
    let value: Double
    var colorByLevel = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(colorByLevel ? levelColor(value) : .accentColor)
                    .frame(width: max(0, proxy.size.width * min(1, value)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// One small vertical bar per logical core, grouped by cluster.
private struct CoreBars: View {
    let cpu: CPUStats

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(groups, id: \.self) { cores in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(cores, id: \.self) { core in
                        let value = cpu.perCore[core]
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(.quaternary)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(levelColor(value))
                                .frame(height: max(1, 28 * value))
                        }
                        .frame(height: 28)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .help("Per-core usage")
    }

    private var groups: [[Int]] {
        let grouped = cpu.clusters.map(\.cores)
        return grouped.isEmpty ? [Array(cpu.perCore.indices)] : grouped
    }
}

private struct Unavailable: View {
    var body: some View {
        Text("Not available on this Mac")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

private func levelColor(_ value: Double) -> Color {
    switch value {
    case ..<0.6: .green
    case ..<0.85: .orange
    default: .red
    }
}
