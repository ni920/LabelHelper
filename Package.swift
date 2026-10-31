// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LabelHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LabelCore", targets: ["LabelCore"]),
        .executable(name: "LabelHelper", targets: ["LabelHelper"]),
        .executable(name: "LabelCoreSelfTest", targets: ["LabelCoreSelfTest"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "LabelCore"),
        .executableTarget(
            name: "LabelHelper",
            dependencies: [
                "LabelCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "LabelCoreSelfTest",
            dependencies: ["LabelCore"]
        )
    ]
)
