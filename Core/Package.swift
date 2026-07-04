// swift-tools-version:5.9
import PackageDescription

// Pure game logic — no SpriteKit/UIKit. Consumed by the app target and
// testable natively on macOS (`cd Core && swift test`) for fast headless
// simulation runs (GOAL §5).
let package = Package(
    name: "NeonHordeCore",
    products: [
        .library(name: "NeonHordeCore", targets: ["NeonHordeCore"]),
    ],
    targets: [
        .target(name: "NeonHordeCore"),
        .testTarget(name: "NeonHordeCoreTests", dependencies: ["NeonHordeCore"]),
    ]
)
