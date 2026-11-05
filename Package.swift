// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TieredCache",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "TieredCache", targets: ["TieredCache"])
    ],
    targets: [
        .target(name: "TieredCache", path: "Sources/TieredCache")
    ]
)
