import Foundation
import Dispatch
import Darwin
import DigitoneAgent

@main
struct DigitoneMCP {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            diagnostic("digitone-mcp [--offline]\nMCP stdio server for Digitone II. stdin/stdout are newline-delimited JSON-RPC.\n--offline disables all hardware I/O; catalog/project/MIDI authoring remains available.\nSee docs/MCP.md for client setup and tools.")
            return
        }
        guard arguments.isEmpty || arguments == ["--offline"] else {
            diagnostic("Unknown arguments. Use digitone-mcp --help."); exit(64)
        }
        let hardware = CoreMIDIAgentHardware(offline: arguments == ["--offline"])
        let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: hardware))
        defer { server.shutdown() }
        // MCP clients close stdin on shutdown, but may also terminate the child.
        // Release scheduled/held notes before obeying those signals.
        let signals = [SIGTERM, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                Task { @MainActor in server.shutdown(); exit(0) }
            }
            source.resume()
            return source
        }
        defer { signals.forEach { $0.cancel() } }
        let reader = MCPLineReader(handle: .standardInput)
        do {
            while let line = try await Task.detached(priority: .userInitiated, operation: { try reader.next() }).value {
                if let response = await server.handle(line) {
                    try FileHandle.standardOutput.write(contentsOf: response + Data([10]))
                }
            }
        } catch { diagnostic("Digitone MCP I/O: \(error.localizedDescription)") }
    }

    private static func diagnostic(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }
}
