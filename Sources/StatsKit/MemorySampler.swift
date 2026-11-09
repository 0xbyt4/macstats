import Darwin
import Foundation

/// Reads memory use with the same formula as Activity Monitor:
/// used = app memory + wired + compressed.
final class MemorySampler {
    private let host = mach_host_self()
    private let total = UInt64(ProcessInfo.processInfo.physicalMemory)
    private lazy var pageSize: UInt64 = {
        var size: vm_size_t = 0
        return host_page_size(host, &size) == KERN_SUCCESS ? UInt64(size) : UInt64(getpagesize())
    }()

    func sample() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let app = UInt64(stats.internal_page_count &- stats.purgeable_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = UInt64(stats.external_page_count + stats.purgeable_count) * pageSize

        return MemoryStats(
            total: total,
            used: min(total, app + wired + compressed),
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: swapUsed(),
            pressure: pressure()
        )
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private func pressure() -> MemoryPressure {
        switch IOKitHelpers.sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: .unknown
        }
    }
}
