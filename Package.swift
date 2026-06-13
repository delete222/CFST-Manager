// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CFSTManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CFSTCore", targets: ["CFSTCore"]),
        .executable(name: "CFSTManager", targets: ["CFSTManagerApp"]),
        .executable(name: "CFSTCoreTestRunner", targets: ["CFSTCoreTestRunner"])
    ],
    targets: [
        .target(name: "CFSTCore"),
        .executableTarget(
            name: "CFSTManagerApp",
            dependencies: ["CFSTCore"]
        ),
        .executableTarget(
            name: "CFSTCoreTestRunner",
            dependencies: ["CFSTCore"]
        )
    ]
)
