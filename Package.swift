// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Room",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "RoomCore", targets: ["RoomCore"]),
        .executable(name: "Room", targets: ["Room"]),
    ],
    targets: [
        .target(name: "RoomCore"),
        .executableTarget(name: "Room", dependencies: ["RoomCore"], exclude: ["Resources"]),
        .testTarget(name: "RoomCoreTests", dependencies: ["RoomCore"]),
    ],
    swiftLanguageModes: [.v5]
)
