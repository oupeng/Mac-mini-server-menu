// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MiniServer",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "minimonitord", targets: ["MiniServer"])
    ],
    targets: [
        .target(
            name: "CSMART",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "MiniServer",
            dependencies: ["CSMART"]
        )
    ]
)
