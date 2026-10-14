// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunCat",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RunCatKit", targets: ["RunCatKit"]),
        .executable(name: "RunCat", targets: ["RunCat"]),
    ],
    targets: [
        .target(
            name: "RunCatKit",
            path: "Sources/RunCatKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "RunCat",
            dependencies: ["RunCatKit"],
            path: "Sources/RunCat",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RunCatKitTests",
            dependencies: ["RunCatKit"],
            path: "Tests/RunCatKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
