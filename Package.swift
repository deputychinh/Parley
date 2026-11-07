// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Parley",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Parley", swiftSettings: [.swiftLanguageMode(.v5)]),
        // `make test`: Swift Testing against the app's logic (run from the package root so Resources/ resolves).
        .testTarget(name: "ParleyTests", dependencies: ["Parley"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
