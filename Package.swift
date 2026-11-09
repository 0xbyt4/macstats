// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacStats", targets: ["MacStats"]),
        .executable(name: "statsprobe", targets: ["statsprobe"]),
    ],
    targets: [
        .target(
            name: "CSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "StatsKit",
            dependencies: ["CSensors"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "MacStats",
            dependencies: ["StatsKit"]
        ),
        .executableTarget(
            name: "statsprobe",
            dependencies: ["StatsKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
