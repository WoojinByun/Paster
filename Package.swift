// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Paster", targets: ["Paster"]),
        .library(name: "PasterCore", targets: ["PasterCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.1.0"),
    ],
    targets: [
        .target(
            name: "PasterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Paster",
            dependencies: [
                "PasterCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(
            name: "PasterCoreTests",
            dependencies: ["PasterCore"]
        ),
    ]
)
