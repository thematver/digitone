import XCTest
import DigitoneCore
@testable import DigitoneAgent

@MainActor
final class FakeAgentHardware: AgentHardware {
    struct Send: Equatable { var id: String; var value: Int; var channel: Int }
    var connected = false
    var sent: [Send] = []
    var played: NoteSequence?
    var sendsClock = false
    var stopCount = 0
    var shutdownCount = 0
    var failAfterSends: Int?
    func listDevices() throws -> JSONValue { .object(["inputs": .array([]), "outputs": .array([])]) }
    func status() -> JSONValue { .object(["connected": .bool(connected), "playing": .bool(played != nil)]) }
    func connect(sourceID: Int32, destinationID: Int32) async throws -> JSONValue {
        guard sourceID == 100, destinationID == 200 else { throw AgentError("Missing endpoint") }
        connected = true; return status()
    }
    func disconnect() { stop(); connected = false }
    func send(parameter: DNParameter, coarseValue: Int, channel: Int) throws {
        guard connected else { throw AgentError("Disconnected") }
        if sent.count == failAfterSends { throw AgentError("Injected output failure") }
        sent.append(Send(id: parameter.id, value: coarseValue, channel: channel))
    }
    func play(sequence: NoteSequence, sendsClock: Bool) throws {
        guard connected else { throw AgentError("Disconnected") }
        played = sequence; self.sendsClock = sendsClock
    }
    func stop() { played = nil; stopCount += 1 }
    func shutdown() { disconnect(); shutdownCount += 1 }
}

@MainActor
final class MCPServerTests: XCTestCase {
    private func request(_ method: String, id: JSONValue? = .integer(1), params: JSONValue? = nil) throws -> Data {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method)]
        if let id { object["id"] = id }; if let params { object["params"] = params }
        return try JSONValue.object(object).data()
    }
    private func response(_ server: DigitoneMCPServer, _ data: Data) async throws -> JSONValue {
        let output = await server.handle(data)
        return try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(output))
    }
    private func initialize(_ server: DigitoneMCPServer, version: String = "2025-11-25") async throws -> JSONValue {
        let response = try await response(server, request("initialize", params: .object([
            "protocolVersion": .string(version), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("offline-test"), "version": .string("1")])
        ])))
        let notification = await server.handle(try request("notifications/initialized", id: nil))
        XCTAssertNil(notification)
        return response
    }
    private func call(_ server: DigitoneMCPServer, _ name: String, _ args: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await response(server, request("tools/call", params: .object(["name": .string(name), "arguments": .object(args)])))
    }

    func testLifecycleAndKnownVersionNegotiation() async throws {
        let hardware = FakeAgentHardware(); let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: hardware))
        let before = try await response(server, request("tools/list"))
        XCTAssertEqual(before["error"]?["code"], .integer(-32002))
        let initialized = try await initialize(server, version: "future-unknown")
        XCTAssertEqual(initialized["result"]?["protocolVersion"], .string("2025-11-25"))
        let listed = try await response(server, request("tools/list", id: .string("a")))
        XCTAssertEqual(listed["id"], .string("a"))
        XCTAssertEqual(listed["result"]?["tools"]?.array?.count, AgentToolCatalog.tools.count)
        XCTAssertTrue(hardware.sent.isEmpty)
        let duplicate = try await response(server, request("initialize"))
        XCTAssertEqual(duplicate["error"]?["code"], .integer(-32600))
    }

    func testMalformedEnvelopesNeverInvokeHardware() async throws {
        let hardware = FakeAgentHardware(); let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: hardware))
        for data in [Data("not json".utf8), Data("[]".utf8), Data("{\"jsonrpc\":\"1.0\",\"method\":\"tools/call\",\"id\":1}".utf8),
                     try request("tools/call", id: .null), try request("tools/call", id: .bool(true)),
                     try request("tools/call", id: .number(1.5))] {
            let value = try await response(server, data)
            XCTAssertNotNil(value["error"])
            XCTAssertNil(value["result"])
        }
        XCTAssertTrue(hardware.sent.isEmpty); XCTAssertNil(hardware.played)
        let bounded = try await response(server, Data(repeating: 32, count: DigitoneMCPServer.maximumMessageBytes + 1))
        XCTAssertEqual(bounded["error"]?["code"], .integer(-32600))
    }

    func testNotificationsNeverCauseToolSideEffectsOrResponses() async throws {
        let hardware = FakeAgentHardware(); let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: hardware))
        _ = try await initialize(server)
        let result = await server.handle(try request("tools/call", id: nil, params: .object(["name": .string("digitone_disconnect")])))
        XCTAssertNil(result); XCTAssertEqual(hardware.stopCount, 0)
        let unknown = await server.handle(try request("notifications/custom", id: nil))
        XCTAssertNil(unknown)
    }

    func testToolErrorsAndUnknownMethodsHaveCorrectLayers() async throws {
        let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: FakeAgentHardware()))
        _ = try await initialize(server)
        let malformed = try await call(server, "digitone_sound_create", ["track": .number(1.5)])
        XCTAssertEqual(malformed["result"]?["isError"], .bool(true)); XCTAssertNil(malformed["error"])
        let unknown = try await call(server, "arbitrary")
        XCTAssertEqual(unknown["error"]?["code"], .integer(-32602))
        let method = try await response(server, request("arbitrary"))
        XCTAssertEqual(method["error"]?["code"], .integer(-32601))
    }

    func testLegacyVersionOmitsStructuredContent() async throws {
        let server = DigitoneMCPServer(workspace: AgentWorkspace(hardware: FakeAgentHardware()))
        let initialized = try await initialize(server, version: "2024-11-05")
        XCTAssertEqual(initialized["result"]?["protocolVersion"], .string("2024-11-05"))
        let output = try await call(server, "digitone_project_get")
        XCTAssertNotNil(output["result"]?["content"]); XCTAssertNil(output["result"]?["structuredContent"])
    }

    func testSoundDraftIsOfflineUntilApplyAndRoutesExplicitly() async throws {
        let hardware = FakeAgentHardware(); let workspace = AgentWorkspace(hardware: hardware)
        let created = try await workspace.call("digitone_sound_create", arguments: [
            "name": .string("Low kick"), "track": .integer(4), "midiChannel": .integer(11), "machine": .string("fmDrum"),
            "parameters": .object(["fmDrum.syn1.tune": .integer(64), "fmDrum.syn1.algo": .integer(0)])
        ])
        XCTAssertEqual(created["track"], .integer(4)); XCTAssertEqual(created["midiChannel"], .integer(11))
        XCTAssertTrue(hardware.sent.isEmpty)
        let id = try XCTUnwrap(created["soundID"])
        _ = try await workspace.call("digitone_connect", arguments: ["sourceID": .integer(100), "destinationID": .integer(200)])
        _ = try await workspace.call("digitone_sound_apply", arguments: ["soundID": id])
        XCTAssertEqual(hardware.sent.map(\.channel), [10, 10]); XCTAssertEqual(hardware.sent.map(\.value), [64, 0])
        XCTAssertEqual(workspace.project.sounds[0].track, 3)
        XCTAssertEqual(workspace.project.sounds[0].snapshot.parameters.count, 2)
    }

    func testCatalogRejectsWrongMachineIDAndNarrowValuesTransactionally() async throws {
        let workspace = AgentWorkspace(hardware: FakeAgentHardware())
        let server = DigitoneMCPServer(workspace: workspace); _ = try await initialize(server)
        let base: [String: JSONValue] = ["name": .string("Invalid"), "track": .integer(1), "midiChannel": .integer(1), "machine": .string("fmTone")]
        for parameters in [["fmDrum.syn1.algo": JSONValue.integer(0)], ["fmTone.syn1.algo": .integer(127)], ["invented": .integer(1)]] {
            var args = base; args["parameters"] = .object(parameters)
            let output = try await call(server, "digitone_sound_create", args)
            XCTAssertEqual(output["result"]?["isError"], .bool(true))
            XCTAssertTrue(workspace.project.sounds.isEmpty)
        }
        let catalog = try await workspace.call("digitone_parameter_catalog", arguments: ["machine": .string("fmTone"), "page": .string("syn1")])
        let algorithm = try XCTUnwrap(catalog["parameters"]?.array?.first(where: { $0["id"] == .string("fmTone.syn1.algo") }))
        XCTAssertEqual(algorithm["minimum"], .integer(0)); XCTAssertEqual(algorithm["maximum"], .integer(7))
    }

    func testApplyReportsPartialOutputFailure() async throws {
        let hardware = FakeAgentHardware(); hardware.connected = true; hardware.failAfterSends = 1
        let draft = AgentSoundDraft(name: "Partial", track: 0, midiChannel: 0, machine: .fmTone,
                                    parameters: ["fmTone.syn1.algo": 0, "fmTone.syn1.feedback": 10])
        let workspace = AgentWorkspace(hardware: hardware, project: AgentProject(sounds: [draft]))
        do {
            _ = try await workspace.call("digitone_sound_apply", arguments: ["soundID": .string(draft.id.uuidString)])
            XCTFail("Expected injected failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Sent 1 of 2")); XCTAssertEqual(hardware.sent.count, 1)
        }
    }

    func testDeterministicBeatAndFractionalStepsUseDeclaredChannel() async throws {
        let hardware = FakeAgentHardware(); let workspace = AgentWorkspace(hardware: hardware)
        _ = try await workspace.call("digitone_pattern_create", arguments: ["name": .string("Beat"), "tempo": .number(137), "bars": .integer(2)])
        let args: [String: JSONValue] = ["track": .integer(2), "midiChannel": .integer(9), "style": .string("euclidean"), "hits": .integer(5), "rotation": .integer(2)]
        _ = try await workspace.call("digitone_beat", arguments: args)
        let first = workspace.project.sequence.lanes[0].notes.map(\.start)
        _ = try await workspace.call("digitone_beat", arguments: args)
        XCTAssertEqual(workspace.project.sequence.lanes[0].notes.map(\.start), first); XCTAssertEqual(first.count, 10)
        XCTAssertEqual(workspace.project.sequence.lanes[0].channel, 8)
        XCTAssertTrue(hardware.sent.isEmpty); XCTAssertNil(hardware.played)
        _ = try await workspace.call("digitone_pattern_set_track", arguments: ["track": .integer(2), "midiChannel": .integer(9), "notes": .array([
            .object(["pitch": .integer(64), "step": .number(1.5), "length": .number(0.5)])
        ])])
        XCTAssertEqual(workspace.project.sequence.lanes[0].notes[0].start, 12)
        XCTAssertEqual(workspace.project.sequence.lanes[0].notes[0].duration, 12)
        hardware.connected = true
        _ = try await workspace.call("digitone_pattern_play", arguments: ["sendsClock": .bool(true)])
        XCTAssertEqual(hardware.played, workspace.project.sequence); XCTAssertTrue(hardware.sendsClock)
        _ = try await workspace.call("digitone_pattern_stop", arguments: [:]); XCTAssertNil(hardware.played)
    }

    func testInvalidTrackEditDoesNotMutateDraft() async throws {
        let hardware = FakeAgentHardware(); let workspace = AgentWorkspace(hardware: hardware)
        let original = workspace.project
        do {
            _ = try await workspace.call("digitone_pattern_set_track", arguments: ["track": .integer(1), "midiChannel": .integer(17), "notes": .array([])])
            XCTFail("Expected range error")
        } catch { XCTAssertEqual(workspace.project, original) }
        let server = DigitoneMCPServer(workspace: workspace); _ = try await initialize(server)
        let extra = try await call(server, "digitone_pattern_stop", ["unexpected": .bool(true)])
        XCTAssertEqual(extra["result"]?["isError"], .bool(true)); XCTAssertEqual(hardware.stopCount, 0)
    }

    func testPortableProjectAndMIDIExportNoClobber() async throws {
        let hardware = FakeAgentHardware(); let workspace = AgentWorkspace(hardware: hardware)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await workspace.call("digitone_beat", arguments: ["track": .integer(1), "midiChannel": .integer(3), "style": .string("four_on_floor")])
        let file = folder.appendingPathComponent("beat.digitone.json")
        _ = try await workspace.call("digitone_project_save", arguments: ["path": .string(file.path)])
        let saved = try Data(contentsOf: file); let decoded = try AgentProject.read(saved)
        XCTAssertEqual(decoded, workspace.project)
        do {
            _ = try await workspace.call("digitone_project_save", arguments: ["path": .string(file.path)])
            XCTFail("Should refuse overwrite")
        } catch { XCTAssertEqual(try Data(contentsOf: file), saved) }
        let midi = folder.appendingPathComponent("beat.mid")
        _ = try await workspace.call("digitone_midi_export", arguments: ["path": .string(midi.path)])
        let sequence = try MIDIFile.read(Data(contentsOf: midi))
        XCTAssertEqual(sequence.noteCount, 4); XCTAssertEqual(sequence.lanes[0].channel, 2)
        _ = try await workspace.call("digitone_project_load", arguments: ["path": .string(file.path)])
        XCTAssertEqual(workspace.project, decoded); XCTAssertTrue(hardware.sent.isEmpty); XCTAssertNil(hardware.played)
        let server = DigitoneMCPServer(workspace: workspace); server.shutdown()
        XCTAssertEqual(hardware.shutdownCount, 1)
    }
}
