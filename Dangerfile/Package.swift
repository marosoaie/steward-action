// swift-tools-version: 6.2
// The checks Steward runs on this repository's pull requests, and the
// fixture the Action's CI runs: `uses: ./` with its default package path.
import PackageDescription

let package = Package(
    name: "Dangerfile",
    platforms: [.macOS(.v26)],
    dependencies: [
        // As in swift-steward's template: no release has Steward yet, so this
        // follows swift-steward's main branch, at the revision
        // Package.resolved pins; `swift package update` moves the pin.
        .package(url: "https://github.com/marosoaie/swift-steward.git", branch: "main"),
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
