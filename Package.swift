// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DigitoneStudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DigitoneCore", targets: ["DigitoneCore"]),
        .library(name: "DigitoneMIDI", targets: ["DigitoneMIDI"]),
        .library(name: "DigitoneDSP", targets: ["DigitoneDSP"]),
        .library(name: "DigitoneAudio", targets: ["DigitoneAudio"]),
        .library(name: "DigitoneKit", targets: ["DigitoneKit"]),
        .library(name: "DigitoneDesign", targets: ["DigitoneDesign"]),
        .library(name: "DigitoneUI", targets: ["DigitoneUI"]),
        .library(name: "DigitoneAgent", targets: ["DigitoneAgent"]),
        .executable(name: "DigitoneStudio", targets: ["DigitoneStudio"]),
        .executable(name: "digitone-mcp", targets: ["DigitoneMCP"]),
        .executable(name: "digitone-tool", targets: ["DigitoneTool"])
    ],
    targets: [
        // Protocol, file formats and musical data. No platform I/O.
        .target(name: "DigitoneCore"),
        // CoreMIDI transport, device session, clock and sequence playback.
        .target(name: "DigitoneMIDI", dependencies: ["DigitoneCore"]),
        // Validated musical projects and the stdio MCP protocol for agent clients.
        .target(name: "DigitoneAgent", dependencies: ["DigitoneCore", "DigitoneMIDI"]),
        .executableTarget(name: "DigitoneMCP", dependencies: ["DigitoneAgent"]),
        // Real-time-safe synthesis and analysis. Pure Swift + Accelerate, no AVFoundation.
        .target(name: "DigitoneDSP"),
        // AVAudioEngine I/O: device routing, monitoring, recording, playback, hosting DSP sources.
        .target(name: "DigitoneAudio", dependencies: ["DigitoneDSP"]),
        // App-level shared state and services used by every mode: device link,
        // track model, parameter truth, transport.
        .target(name: "DigitoneKit", dependencies: ["DigitoneCore", "DigitoneMIDI", "DigitoneDSP", "DigitoneAudio"]),
        // Design tokens, drawn components and snapshot rendering support.
        .target(name: "DigitoneDesign"),
        .target(name: "DigitoneUI", dependencies: ["DigitoneCore", "DigitoneMIDI", "DigitoneDesign", "DigitoneAudio", "DigitoneDSP", "DigitoneAgent"]),
        .executableTarget(name: "DigitoneStudio", dependencies: ["DigitoneUI"]),
        .executableTarget(name: "DigitoneTool", dependencies: ["DigitoneCore", "DigitoneMIDI", "DigitoneAudio", "DigitoneDSP"]),
        // Renders every registered screen state to PNG for visual review.
        .executableTarget(name: "DigitoneSnapshots", dependencies: ["DigitoneUI", "DigitoneDesign"]),
        .testTarget(name: "DigitoneCoreTests", dependencies: ["DigitoneCore"]),
        .testTarget(name: "DigitoneMIDITests", dependencies: ["DigitoneMIDI", "DigitoneCore"]),
        .testTarget(name: "DigitoneAgentTests", dependencies: ["DigitoneAgent", "DigitoneCore"]),
        .testTarget(name: "DigitoneDSPTests", dependencies: ["DigitoneDSP"]),
        .testTarget(name: "DigitoneAudioTests", dependencies: ["DigitoneAudio", "DigitoneDSP"]),
        .testTarget(name: "DigitoneUITests", dependencies: ["DigitoneUI", "DigitoneCore", "DigitoneAgent"])
    ]
)
