import Foundation
import CoreMIDI
import DigitoneCore

public struct MIDIEndpoint: Identifiable, Equatable, Sendable {
    public let reference: MIDIEndpointRef
    public let uniqueID: MIDIUniqueID
    public let name: String
    public var id: MIDIEndpointRef { reference }
    public var isElektron: Bool { name.localizedCaseInsensitiveContains("digitone") }
}

public enum MIDIConnectionError: Error, LocalizedError {
    case system(String, OSStatus)
    case disconnected
    case timeout(String)
    case wrongDevice(String)
    public var errorDescription: String? {
        switch self {
        case .system(let operation, let status):
            if status == -10833 { return "MIDI-служба macOS недоступна. Запусти приложение обычным способом на Mac и обнови подключение." }
            return "MIDI недоступен: \(operation) (\(status))."
        case .disconnected: return "Выбери вход и выход Digitone и подключись."
        case .timeout(let operation): return "Digitone не ответил: \(operation). Проверь USB-режим и MIDI-порты."
        case .wrongDevice(let name): return "Выбран \(name). Эта версия работает с Digitone II."
        }
    }
}

@MainActor
public final class MIDITransport {
    public private(set) var sources: [MIDIEndpoint] = []
    public private(set) var destinations: [MIDIEndpoint] = []
    public private(set) var source: MIDIEndpoint?
    public private(set) var destination: MIDIEndpoint?
    public var onMessages: (([MIDIMessage]) -> Void)?
    public var onEndpointsChanged: (() -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onWillDisconnect: (() -> Void)?
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var output: MIDIPortRef = 0
    private var decoder = MIDIStreamDecoder()
    private var connectionEpoch: UInt = 0

    public init() throws {
        try check(MIDIClientCreateWithBlock("Digitone Studio" as CFString, &client) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }, "создание MIDI-клиента")
        do {
            try check(MIDIInputPortCreateWithBlock(client, "Digitone input" as CFString, &input) { [weak self] list, context in
                // Copy before the CoreMIDI callback returns; packet storage is borrowed.
                let copied = Self.copyPackets(from: list)
                let epoch = UInt(bitPattern: context)
                Task { @MainActor [weak self] in
                    guard let self, epoch == self.connectionEpoch else { return }
                    for chunk in copied { self.onMessages?(self.decoder.feed(chunk)) }
                }
            }, "создание MIDI-входа")
            try check(MIDIOutputPortCreate(client, "Digitone output" as CFString, &output), "создание MIDI-выхода")
            refresh()
        } catch {
            if input != 0 { MIDIPortDispose(input) }
            if output != 0 { MIDIPortDispose(output) }
            MIDIClientDispose(client)
            throw error
        }
    }

    public func refresh() {
        sources = (0..<MIDIGetNumberOfSources()).compactMap { endpoint(MIDIGetSource($0)) }
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { endpoint(MIDIGetDestination($0)) }
        if let source, !sources.contains(where: { $0.reference == source.reference }),
           destination != nil { disconnect() }
        if let destination, !destinations.contains(where: { $0.reference == destination.reference }) { disconnect() }
        onEndpointsChanged?()
    }

    public func connect(source: MIDIEndpoint, destination: MIDIEndpoint) throws {
        disconnect()
        try check(MIDIPortConnectSource(input, source.reference, UnsafeMutableRawPointer(bitPattern: connectionEpoch)), "подключение входа")
        self.source = source
        self.destination = destination
        decoder = MIDIStreamDecoder()
    }

    public func disconnect() {
        let wasConnected = source != nil || destination != nil
        if wasConnected { onWillDisconnect?() }
        if let source { MIDIPortDisconnectSource(input, source.reference) }
        connectionEpoch &+= 1
        if connectionEpoch == 0 { connectionEpoch = 1 }
        source = nil
        destination = nil
        decoder = MIDIStreamDecoder()
        if wasConnected { onDisconnect?() }
    }

    public func close() {
        disconnect()
        if input != 0 { MIDIPortDispose(input); input = 0 }
        if output != 0 { MIDIPortDispose(output); output = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    public func send(_ bytes: [UInt8], at time: MIDITimeStamp = 0) throws {
        guard let destination else { throw MIDIConnectionError.disconnected }
        guard !bytes.isEmpty, bytes.count <= 1024 else { throw ProtocolError.unsupported("outgoing packet size") }
        let size = MemoryLayout<MIDIPacketList>.size + bytes.count + 32
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let first = MIDIPacketListInit(list)
        _ = bytes.withUnsafeBufferPointer { buffer in
            MIDIPacketListAdd(list, size, first, time, bytes.count, buffer.baseAddress!)
        }
        try check(MIDISend(output, destination.reference, list), "отправка MIDI")
    }

    nonisolated static func copyPackets(from list: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var chunks: [[UInt8]] = []
        var current = UnsafeRawPointer(list)
            .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            // MIDIPacket.data's imported tuple has 256 bytes, but actual packets
            // have variable-length storage and may be much larger than the tuple.
            let bytes = UnsafeRawPointer(current)
                .advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
                .assumingMemoryBound(to: UInt8.self)
            chunks.append(Array(UnsafeBufferPointer(start: bytes, count: Int(current.pointee.length))))
            current = UnsafePointer(MIDIPacketNext(current))
        }
        return chunks
    }

    private func endpoint(_ reference: MIDIEndpointRef) -> MIDIEndpoint? {
        guard reference != 0 else { return nil }
        var name: Unmanaged<CFString>?
        var identifier: Int32 = 0
        MIDIObjectGetStringProperty(reference, kMIDIPropertyDisplayName, &name)
        MIDIObjectGetIntegerProperty(reference, kMIDIPropertyUniqueID, &identifier)
        return MIDIEndpoint(reference: reference, uniqueID: identifier, name: name?.takeRetainedValue() as String? ?? "MIDI \(reference)")
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw MIDIConnectionError.system(operation, status) }
    }
}
