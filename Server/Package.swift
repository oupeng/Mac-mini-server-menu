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
            name: "MiniServer",
            dependencies: [],
            cSettings: [
                .unsafeFlags(["-Ounchecked"]) // 极限优化，降低开销
            ]
        )
    ]
)
