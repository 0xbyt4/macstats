import Foundation
import IOKit

enum IOKitHelpers {
    /// Returns the properties of every service that matches `className`.
    static func properties(ofClass className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                result.append(dict)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    /// Returns one property of every service that matches `className`.
    /// This is much cheaper than copying all properties.
    static func property(_ key: String, ofClass className: String) -> [Any] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [Any] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                result.append(value)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// IOKit stores some signed values as unsigned 64-bit numbers.
    static func signedInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return Int(Int64(bitPattern: number.uint64Value))
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // The kernel writes 4 or 8 bytes depending on the key.
        return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }
}
