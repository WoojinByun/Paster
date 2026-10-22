// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PasterCore", targets: ["PasterCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "PasterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "PasterCoreTests",
            dependencies: ["PasterCore"]
        ),
    ]
)
