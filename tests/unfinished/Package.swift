// swift-tools-version: 6.2
// Dangerfiles that end without reporting, for the CI's checks of the
// summary comment the Action leaves then (.github/workflows/steward.yml and
// ci.yml): `Stops` ends as its STOP variable says, and `Broken` doesn't
// build.
import PackageDescription

let package = Package(
    name: "Unfinished",
    targets: [
        .executableTarget(name: "Stops"),
        .executableTarget(name: "Broken"),
    ]
)
