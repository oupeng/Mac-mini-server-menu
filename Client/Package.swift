// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniBar",
    platforms: [
        .macOS(.v14) // 适用于现代 macOS 26 的原生 API
    ],
    products: [
        .executable(name: "MiniBar", targets: ["MiniBar"])
    ],
    targets: [
        .executableTarget(
            name: "MiniBar",
            path: "MiniBar"
        )
    ]
)
