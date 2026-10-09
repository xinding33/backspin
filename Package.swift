// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Backspin",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Backspin", targets: ["Backspin"])],
    targets: [
        .target(name: "BackspinCore"),
        .executableTarget(name: "Backspin", dependencies: ["BackspinCore"]),
        .testTarget(name: "BackspinCoreTests", dependencies: ["BackspinCore"]),
    ]
)
