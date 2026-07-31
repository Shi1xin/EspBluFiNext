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
    targets: [
        .target(name: "BluFiKit"),
        .testTarget(name: "BluFiKitTests", dependencies: ["BluFiKit"])
    ]
)
