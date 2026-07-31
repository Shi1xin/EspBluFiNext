// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BluFiKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "BluFiKit", targets: ["BluFiKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "BluFiKit", dependencies: ["BigInt"]),
        .testTarget(name: "BluFiKitTests", dependencies: ["BluFiKit"])
    ]
)
