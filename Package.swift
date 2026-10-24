// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BarrioMesh",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "BarrioMeshCore", targets: ["BarrioMeshCore"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
        .executable(name: "FaroSim", targets: ["FaroSim"])
    ],
    targets: [
        .target(name: "BarrioMeshCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["BarrioMeshCore"]),
        .executableTarget(name: "FaroSim", dependencies: ["BarrioMeshCore"]),
        .testTarget(name: "BarrioMeshCoreTests", dependencies: ["BarrioMeshCore"])
    ]
)
