import Foundation

/// Single-consumer bounded reader. Call next() off the main actor so waiting on stdin
/// does not block CoreMIDI callbacks, playback pumping or identification timeouts.
public final class MCPLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let maximum: Int
    private var buffer = Data()
    private var ended = false
    private var discarding = false

    public init(handle: FileHandle, maximumMessageBytes: Int = DigitoneMCPServer.maximumMessageBytes) {
        self.handle = handle; maximum = maximumMessageBytes
    }

    /// Oversized lines are drained and represented by a bounded invalid message.
    /// A final message without a newline is accepted before EOF.
    public func next() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let prefix = buffer[..<newline]
                let tooLarge = discarding || prefix.count > maximum
                let line = tooLarge ? Data(repeating: 32, count: maximum + 1) : Data(prefix)
                buffer.removeSubrange(...newline); discarding = false
                return line
            }
            if ended {
                guard !buffer.isEmpty || discarding else { return nil }
                let line = discarding ? Data(repeating: 32, count: maximum + 1) : buffer
                buffer = Data(); discarding = false
                return line
            }
            if buffer.count > maximum { buffer.removeAll(keepingCapacity: false); discarding = true }
            if let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty { buffer.append(chunk) }
            else { ended = true }
        }
    }
}
