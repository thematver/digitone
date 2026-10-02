// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DigitoneStudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DigitoneCore", targets: ["DigitoneCore"]),
        .library(name: "DigitoneMIDI", targets: ["DigitoneMIDI"]),
        .library(name: "DigitoneUI", targets: ["DigitoneUI"]),
        .executable(name: "DigitoneStudio", targets: ["DigitoneStudio"]),
        .executable(name: "digitone-tool", targets: ["DigitoneTool"])
    ],
    targets: [
        .target(name: "DigitoneCore"),
        .target(name: "DigitoneMIDI", dependencies: ["DigitoneCore"]),
        .target(name: "DigitoneUI", dependencies: ["DigitoneCore", "DigitoneMIDI"]),
        .executableTarget(name: "DigitoneStudio", dependencies: ["DigitoneUI"]),
        .executableTarget(name: "DigitoneTool", dependencies: ["DigitoneCore", "DigitoneMIDI"]),
        .testTarget(name: "DigitoneCoreTests", dependencies: ["DigitoneCore"]),
        .testTarget(name: "DigitoneMIDITests", dependencies: ["DigitoneMIDI", "DigitoneCore"])
    ]
)
