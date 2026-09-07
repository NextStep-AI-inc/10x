// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ComputerKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComputerKit", targets: ["ComputerKit"]),
        .executable(name: "tenx-computer", targets: ["TenXComputer"]),
    ],
    targets: [
        .target(name: "ComputerKit"),
        .executableTarget(
            name: "TenXComputer",
            dependencies: ["ComputerKit"],
            path: "Sources/tenx-computer"
        ),
        .testTarget(name: "ComputerKitTests", dependencies: ["ComputerKit"]),
    ]
)
