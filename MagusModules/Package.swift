// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagusModules",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MagusCommon", targets: ["MagusCommon"]),
        .library(name: "MagusCore", targets: ["MagusCore"]),
        .library(name: "MagusUI", targets: ["MagusUI"]),
        .library(name: "MagusPerception", targets: ["MagusPerception"]),
        .library(name: "MagusDecision", targets: ["MagusDecision"]),
        .library(name: "MagusExecution", targets: ["MagusExecution"]),
        .library(name: "MagusPersistence", targets: ["MagusPersistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MagusCommon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusCore",
            dependencies: ["MagusCommon"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusUI",
            dependencies: ["MagusCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusPerception",
            dependencies: ["MagusCore", "MagusCommon"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusDecision",
            dependencies: ["MagusCore", "MagusCommon"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusExecution",
            dependencies: ["MagusCore", "MagusCommon"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusPersistence",
            dependencies: [
                "MagusCore",
                "MagusCommon",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MagusCoreTests",
            dependencies: ["MagusCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
