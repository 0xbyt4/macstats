import Darwin
import Foundation

/// Reads network speed from the 64-bit interface counters (NET_RT_IFLIST2).
/// The loopback interface is not counted.
final class NetworkSampler {
    private var previous: (date: Date, down: UInt64, up: UInt64)?

    func sample() -> NetworkStats? {
        guard let (down, up) = readCounters() else { return nil }
        let now = Date()
        defer { previous = (now, down, up) }
        guard let previous, down >= previous.down, up >= previous.up else {
            return NetworkStats(downBytesPerSecond: 0, upBytesPerSecond: 0)
        }
        let seconds = now.timeIntervalSince(previous.date)
        guard seconds > 0 else { return NetworkStats(downBytesPerSecond: 0, upBytesPerSecond: 0) }
        return NetworkStats(
            downBytesPerSecond: Double(down - previous.down) / seconds,
            upBytesPerSecond: Double(up - previous.up) / seconds
        )
    }

    private func readCounters() -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var down: UInt64 = 0
        var up: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if msg.ifm_flags & IFF_LOOPBACK == 0 {
                        down &+= msg.ifm_data.ifi_ibytes
                        up &+= msg.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (down, up)
    }
}
