// swift-tools-version: 6.2

import PackageDescription

let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let mainActorSettings = commonSettings + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "MarcKit",
    defaultLocalization: "en",
    platforms: [.macOS("15.4")],
    products: [
        .library(
            name: "MarcKit",
            targets: ["MarcCore", "MarcPersistence", "MarcWebKit", "MarcPlatform", "MarcDesignSystem", "MarcUI"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
    ],
    targets: [
        .target(name: "MarcCore", resources: [.process("Resources")], swiftSettings: commonSettings),
        .target(
            name: "MarcPersistence",
            dependencies: ["MarcCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: commonSettings,
        ),
        .target(
            name: "MarcWebKit",
            dependencies: ["MarcCore"],
            resources: [.process("Resources")],
            swiftSettings: mainActorSettings,
        ),
        .target(name: "MarcPlatform", dependencies: ["MarcCore"], swiftSettings: commonSettings),
        .target(name: "MarcDesignSystem", swiftSettings: mainActorSettings),
        .target(
            name: "MarcUI",
            dependencies: ["MarcCore", "MarcDesignSystem", "MarcWebKit"],
            resources: [.process("Resources")],
            swiftSettings: mainActorSettings,
        ),

        .testTarget(
            name: "MarcCoreTests",
            dependencies: ["MarcCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: commonSettings,
        ),
        .testTarget(
            name: "MarcPersistenceTests",
            dependencies: ["MarcPersistence", "MarcCore"],
            swiftSettings: commonSettings,
        ),
        .testTarget(
            name: "MarcWebKitTests",
            dependencies: ["MarcWebKit", "MarcCore"],
            swiftSettings: mainActorSettings,
        ),
        .testTarget(
            name: "MarcPlatformTests",
            dependencies: ["MarcPlatform", "MarcCore"],
            swiftSettings: commonSettings,
        ),
        .testTarget(
            name: "MarcDesignSystemTests",
            dependencies: ["MarcDesignSystem"],
            swiftSettings: mainActorSettings,
        ),
        .testTarget(
            name: "MarcUIFeatureTests",
            dependencies: ["MarcUI", "MarcCore", "MarcWebKit"],
            swiftSettings: mainActorSettings,
        ),
    ],
)
