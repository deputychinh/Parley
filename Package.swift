// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Parley",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Parley", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
