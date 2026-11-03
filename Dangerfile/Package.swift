// swift-tools-version: 6.2
// The checks Steward runs on this repository's pull requests, and the
// fixture the Action's CI runs: `uses: ./` with its default package path.
import PackageDescription

let package = Package(
    name: "Dangerfile",
    platforms: [.macOS(.v26)],
    dependencies: [
        // As in swift-steward's template: Steward 0.1.x, at the release
        // Package.resolved pins; `swift package update` takes its fixes.
        .package(url: "https://github.com/marosoaie/swift-steward.git", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .executableTarget(
            name: "Dangerfile",
            dependencies: [.product(name: "Steward", package: "swift-steward")]
        ),
        .testTarget(
            name: "DangerfileTests",
            dependencies: ["Dangerfile", .product(name: "StewardTesting", package: "swift-steward")]
        ),
    ]
)
