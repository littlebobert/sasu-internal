// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sasu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Sasu", targets: ["Sasu"])
    ],
    targets: [
        .executableTarget(
            name: "Sasu",
            path: "Sources/Sasu"
        )
    ]
)
