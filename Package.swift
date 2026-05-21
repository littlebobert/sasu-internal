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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "Sasu",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Sasu",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
