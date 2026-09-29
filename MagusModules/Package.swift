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
        .library(name: "MagusReferenceData", targets: ["MagusReferenceData"]),
        .library(name: "MagusNetwork", targets: ["MagusNetwork"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // VLM (Qwen2.5-VL via MLX) — fallback OCR quand Vision a une confiance basse.
        // Le bundle examples contient MLXVLM avec les helpers de model loading.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.0"),
        // Décodage Protobuf des paquets observés sur le réseau Dofus (MagusNetwork).
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
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
            dependencies: [
                "MagusCore",
                "MagusCommon",
                .product(name: "MLXVLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
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
        .target(
            name: "MagusReferenceData",
            dependencies: [
                "MagusCore",
                "MagusCommon",
                "MagusPersistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MagusNetwork",
            dependencies: [
                "MagusCore",
                "MagusCommon",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            exclude: [
                // Protos sources + script de génération + helper Node.js : pas du Swift.
                "Protos/clear",
                "Protos/generate.sh",
                "Protos/Generated/_README.md",
                "Frida",
                "README.md",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MagusCoreTests",
            dependencies: ["MagusCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MagusPerceptionTests",
            dependencies: ["MagusPerception", "MagusCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
