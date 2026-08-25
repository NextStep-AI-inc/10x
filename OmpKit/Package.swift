// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "OmpKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OmpKit", targets: ["OmpKit"])],
    targets: [
        .target(name: "OmpKit"),
        .testTarget(
            name: "OmpKitTests",
            dependencies: ["OmpKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
