import Foundation

/// Reads free space of the startup volume and read/write speed of all block storage drivers.
final class DiskSampler {
    private var previous: (date: Date, read: UInt64, write: UInt64)?

    func sample() -> DiskStats? {
        let now = Date()
        var read: UInt64 = 0
        var write: UInt64 = 0
        for value in IOKitHelpers.property("Statistics", ofClass: "IOBlockStorageDriver") {
            guard let stats = value as? [String: Any] else { continue }
            read += UInt64(max(0, IOKitHelpers.int(stats["Bytes (Read)"]) ?? 0))
            write += UInt64(max(0, IOKitHelpers.int(stats["Bytes (Write)"]) ?? 0))
        }

        var readRate = 0.0
        var writeRate = 0.0
        if let previous {
            let seconds = now.timeIntervalSince(previous.date)
            if seconds > 0 {
                readRate = Double(read &- previous.read) / seconds
                writeRate = Double(write &- previous.write) / seconds
                // A counter reset (for example a removed disk) gives a huge wrapped value.
                if read < previous.read { readRate = 0 }
                if write < previous.write { writeRate = 0 }
            }
        }
        previous = (now, read, write)

        guard let space = volumeSpace(now: now) else { return nil }
        return DiskStats(total: space.total, available: space.available, readBytesPerSecond: readRate, writeBytesPerSecond: writeRate)
    }

    private static let spaceRefreshInterval: TimeInterval = 30
    private var space: (date: Date, total: UInt64, available: UInt64)?

    /// Free space changes slowly and costs several milliseconds to read, so it is cached.
    private func volumeSpace(now: Date) -> (total: UInt64, available: UInt64)? {
        if let space, now.timeIntervalSince(space.date) < Self.spaceRefreshInterval {
            return (space.total, space.available)
        }
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        space = (now, UInt64(total), UInt64(available))
        return (UInt64(total), UInt64(available))
    }
}
