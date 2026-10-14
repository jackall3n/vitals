// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VitalsKit", targets: ["VitalsKit"]),
        .executable(name: "Vitals", targets: ["Vitals"]),
    ],
    targets: [
        .target(
            name: "VitalsKit",
            path: "Sources/VitalsKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Vitals",
            dependencies: ["VitalsKit"],
            path: "Sources/Vitals",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VitalsKitTests",
            dependencies: ["VitalsKit"],
            path: "Tests/VitalsKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
