import Foundation

/// Reads GPU load from the "PerformanceStatistics" property of the IOAccelerator service.
final class GPUSampler {
    private lazy var coreCount: Int? = IOKitHelpers.property("gpu-core-count", ofClass: "IOAccelerator")
        .lazy.compactMap(IOKitHelpers.int).first

    func sample() -> GPUStats? {
        for value in IOKitHelpers.property("PerformanceStatistics", ofClass: "IOAccelerator") {
            guard let stats = value as? [String: Any],
                  let device = IOKitHelpers.int(stats["Device Utilization %"]) else {
                continue
            }
            return GPUStats(
                device: Double(device) / 100,
                renderer: Double(IOKitHelpers.int(stats["Renderer Utilization %"]) ?? 0) / 100,
                tiler: Double(IOKitHelpers.int(stats["Tiler Utilization %"]) ?? 0) / 100,
                memoryInUse: UInt64(max(0, IOKitHelpers.int(stats["In use system memory"]) ?? 0)),
                coreCount: coreCount
            )
        }
        return nil
    }
}
