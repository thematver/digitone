import Foundation

/// A dependency-free MCP stdio endpoint, pinned to published protocol revisions.
/// No requests, notifications or diagnostics are printed by this library.
@MainActor
public final class DigitoneMCPServer {
    public nonisolated static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public nonisolated static let maximumMessageBytes = 1_048_576
    public let workspace: AgentWorkspace
    private enum Phase { case new, negotiating, ready }
    private var phase = Phase.new
    private var protocolVersion = supportedProtocolVersions[0]

    public init(workspace: AgentWorkspace) { self.workspace = workspace }

    /// One newline-delimited message in, zero or one newline-free response out.
    public func handle(_ data: Data) async -> Data? {
        guard data.count <= Self.maximumMessageBytes else {
            return encode(error(id: .null, code: -32600, message: "Message exceeds 1 MiB."))
        }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { return encode(self.error(id: .null, code: -32700, message: "Parse error")) }
        guard let request = value.object, request["jsonrpc"] == .string("2.0"), let method = request["method"]?.string,
              !method.isEmpty, method.utf8.count <= 256 else {
            return encode(error(id: .null, code: -32600, message: "Invalid Request"))
        }
        let id = request["id"]
        if let id, !validID(id) { return encode(error(id: .null, code: -32600, message: "Request ID must be a string or integer.")) }
        let isNotification = id == nil
        if let params = request["params"], params.object == nil {
            return isNotification ? nil : encode(error(id: id!, code: -32602, message: "MCP params must be an object."))
        }
        let params = request["params"]?.object ?? [:]
        if isNotification {
            // Notifications never receive responses and never invoke a hardware tool.
            if method == "notifications/initialized", phase == .negotiating { phase = .ready }
            return nil
        }
        let responseID = id!
        if method == "ping" { return encode(result(id: responseID, value: .object([:]))) }
        if method == "initialize" {
            guard phase == .new else { return encode(error(id: responseID, code: -32600, message: "Already initialized")) }
            guard let requested = params["protocolVersion"]?.string, !requested.isEmpty,
                  params["capabilities"]?.object != nil, let client = params["clientInfo"]?.object,
                  client["name"]?.string != nil, client["version"]?.string != nil else {
                return encode(error(id: responseID, code: -32602, message: "initialize requires protocolVersion, capabilities and clientInfo {name, version}."))
            }
            protocolVersion = Self.supportedProtocolVersions.contains(requested) ? requested : Self.supportedProtocolVersions[0]
            phase = .negotiating
            return encode(result(id: responseID, value: .object([
                "protocolVersion": .string(protocolVersion), "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string("digitone-studio"), "version": .string("1.0.0")]),
                "instructions": .string("Digitone II. Discover catalog and exact endpoint IDs first. Tool tracks/channels/steps are 1-based; channel must match MIDI CONFIG → CHANNELS. Sound drafts and local patterns do not send MIDI until sound_apply or pattern_play. Hardware machine selection cannot be changed/read by this server. Patterns stream MIDI notes, not SysEx writes to hardware memory. Save .digitone.json for Studio import. Unspecified sound parameters remain unknown. Never imply hardware presets were read or saved.")
            ])))
        }
        guard phase == .ready else {
            return encode(error(id: responseID, code: -32002, message: "Send initialize, then notifications/initialized, before using tools."))
        }
        switch method {
        case "tools/list":
            guard params["cursor"] == nil else { return encode(error(id: responseID, code: -32602, message: "This server has a single tool page; omit cursor.")) }
            return encode(result(id: responseID, value: .object(["tools": .array(AgentToolCatalog.tools)])))
        case "tools/call":
            guard let name = params["name"]?.string, AgentToolCatalog.names.contains(name),
                  params["arguments"] == nil || params["arguments"]?.object != nil,
                  params["task"] == nil else {
                return encode(error(id: responseID, code: -32602, message: "Unknown tool, invalid arguments object, or unsupported task execution."))
            }
            do {
                let output = try await workspace.call(name, arguments: params["arguments"]?.object ?? [:])
                return encode(result(id: responseID, value: toolResult(output, isError: false)))
            } catch {
                return encode(result(id: responseID, value: toolResult(.object(["error": .string(error.localizedDescription)]), isError: true)))
            }
        default: return encode(error(id: responseID, code: -32601, message: "Method not found"))
        }
    }

    public func shutdown() { workspace.hardware.shutdown() }

    private func validID(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let value): return value.utf8.count <= 256
        case .number(let value): return value.isFinite && value.rounded(.towardZero) == value && abs(value) <= 9_007_199_254_740_991
        default: return false
        }
    }
    private func result(id: JSONValue, value: JSONValue) -> JSONValue { .object(["jsonrpc": .string("2.0"), "id": id, "result": value]) }
    private func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .integer(code), "message": .string(message)])])
    }
    private func encode(_ value: JSONValue) -> Data? { try? value.data() }
    private func toolResult(_ output: JSONValue, isError: Bool) -> JSONValue {
        let text = (try? output.data()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var result: [String: JSONValue] = ["content": .array([.object(["type": .string("text"), "text": .string(text)])]), "isError": .bool(isError)]
        // Structured tool content was introduced in June 2025. Older clients get text JSON.
        if ["2025-11-25", "2025-06-18"].contains(protocolVersion) { result["structuredContent"] = output }
        return .object(result)
    }
}
