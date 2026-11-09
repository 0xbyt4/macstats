import Darwin
import Foundation
import IOKit

/// Reads CPU usage from per-core tick counters. Usage is the change between two calls.
final class CPUSampler {
    private struct Ticks {
        var busy: UInt64
        var total: UInt64
    }

    private struct Cluster {
        let name: String
        let cores: [Int]
    }

    private let host = mach_host_self()
    private var previous: [Ticks] = []
    private lazy var clusters: [Cluster] = Self.detectClusters()

    func sample() -> CPUStats? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard previous.count == current.count else { return nil }

        let perCore: [Double] = zip(previous, current).map { old, new in
            let total = new.total &- old.total
            let busy = new.busy &- old.busy
            return total > 0 ? min(1, Double(busy) / Double(total)) : 0
        }
        let busySum = zip(previous, current).reduce(0.0) { $0 + Double($1.1.busy &- $1.0.busy) }
        let totalSum = zip(previous, current).reduce(0.0) { $0 + Double($1.1.total &- $1.0.total) }

        let clusterUsage = clusters.compactMap { cluster -> ClusterUsage? in
            let cores = cluster.cores.filter { $0 < perCore.count }
            guard !cores.isEmpty else { return nil }
            let usage = cores.map { perCore[$0] }.reduce(0, +) / Double(cores.count)
            return ClusterUsage(name: cluster.name, cores: cores, usage: usage)
        }

        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)

        return CPUStats(
            total: totalSum > 0 ? busySum / totalSum : 0,
            perCore: perCore,
            clusters: clusterUsage,
            loadAverage: (load[0], load[1], load[2])
        )
    }

    private func readTicks() -> [Ticks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else {
            return nil
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        return (0..<Int(cpuCount)).map { cpu in
            let base = cpu * Int(CPU_STATE_MAX)
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            let user = ticks(CPU_STATE_USER)
            let system = ticks(CPU_STATE_SYSTEM)
            let nice = ticks(CPU_STATE_NICE)
            let idle = ticks(CPU_STATE_IDLE)
            return Ticks(busy: user + system + nice, total: user + system + nice + idle)
        }
    }

    /// Groups logical CPUs by the "cluster-type" property in the device tree
    /// and names each group with the matching macOS performance level name.
    private static func detectClusters() -> [Cluster] {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var coresByType: [String: [Int]] = [:]
        var typeOrder: [String] = []
        var child = IOIteratorNext(iterator)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }
            guard let id = property(child, "logical-cpu-id").flatMap(cpuID),
                  let typeData = property(child, "cluster-type") as? Data,
                  let type = String(data: typeData, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters),
                  !type.isEmpty else {
                continue
            }
            if coresByType[type] == nil { typeOrder.append(type) }
            coresByType[type, default: []].append(id)
        }

        // macOS exposes performance levels from fastest (perflevel0) to slowest.
        let levelCount = IOKitHelpers.sysctlInt("hw.nperflevels") ?? 0
        var levels: [(name: String, cores: Int)] = (0..<levelCount).compactMap { level in
            guard let name = IOKitHelpers.sysctlString("hw.perflevel\(level).name"),
                  let cores = IOKitHelpers.sysctlInt("hw.perflevel\(level).logicalcpu") else { return nil }
            return (name, cores)
        }

        var result: [(level: Int, cluster: Cluster)] = []
        for type in typeOrder {
            let cores = coresByType[type, default: []].sorted()
            if let index = levels.firstIndex(where: { $0.cores == cores.count }) {
                result.append((index, Cluster(name: levels[index].name, cores: cores)))
                levels[index] = (levels[index].name, -1)
            } else {
                result.append((Int.max, Cluster(name: "Cluster \(type)", cores: cores)))
            }
        }
        return result.sorted { $0.level < $1.level }.map(\.cluster)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func cpuID(_ value: Any) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let data = value as? Data, data.count >= 4 {
            return Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        return nil
    }
}
