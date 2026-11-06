// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Room",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "RoomCore", targets: ["RoomCore"]),
        .executable(name: "Room", targets: ["Room"]),
        .executable(name: "room-icon", targets: ["room-icon"]),
    ],
    targets: [
        .target(name: "RoomCore"),
        .executableTarget(name: "Room", dependencies: ["RoomCore"], exclude: ["Resources"]),
        .executableTarget(name: "room-icon", dependencies: ["RoomCore"]),
        .testTarget(name: "RoomCoreTests", dependencies: ["RoomCore"]),
    ],
    swiftLanguageModes: [.v5]
)
