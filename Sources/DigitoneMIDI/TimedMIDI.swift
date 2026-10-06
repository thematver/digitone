import Foundation
import CoreMIDI
import DigitoneCore

/// Complete MIDI message bytes to be delivered at a host time (0 = now).
public struct TimedMIDIEvent: Hashable, Sendable {
    public var hostTime: UInt64
    public var bytes: [UInt8]
    public init(hostTime: UInt64, bytes: [UInt8]) { self.hostTime = hostTime; self.bytes = bytes }
}

/// One received CoreMIDI packet. `hostTime` is never 0: packets stamped
/// "now" get the receipt time.
public struct TimedPacket: Hashable, Sendable {
    public var bytes: [UInt8]
    public var hostTime: UInt64
}

/// A thread-safe sink for scheduled MIDI. Real-time engines send through it
/// from their own queue, never through the main actor.
public protocol TimedMIDIOutput: Sendable {
    func send(_ events: [TimedMIDIEvent]) throws
    /// Drops everything scheduled but not yet delivered.
    func flush()
}

/// Sends directly with `MIDISend`; safe from any thread. Captured from a
/// connected `MIDITransport`; a later disconnect makes sends fail, not crash.
public struct CoreMIDIOutput: TimedMIDIOutput {
    let connection: TimedMIDIConnection
    public var destination: MIDIEndpointRef { connection.destination }

    public func send(_ events: [TimedMIDIEvent]) throws {
        try connection.send(events)
    }

    public func flush() { connection.flush() }
}

/// Keeps captured senders tied to one connection even when the endpoint is
/// still present after disconnect. Its lock also protects background sends
/// from racing port disposal on the main actor.
final class TimedMIDIConnection: @unchecked Sendable {
    let port: MIDIPortRef
    let destination: MIDIEndpointRef
    private let lock = NSLock()
    private var isValid = true
    private var notes = Set<Int>()
    private var decoder = MIDIStreamDecoder()

    init(port: MIDIPortRef, destination: MIDIEndpointRef) {
        self.port = port
        self.destination = destination
    }

    func send(_ events: [TimedMIDIEvent]) throws {
        lock.lock()
        defer { lock.unlock() }
        guard isValid else { throw MIDIConnectionError.disconnected }
        // Keep every potentially sounding note: a later flush may discard its
        // scheduled note-off. The set is bounded by 16 * 128 pitches.
        for event in events {
            for message in decoder.feed(event.bytes) {
                if case .channel(let status, let data) = message,
                   status & 0xf0 == 0x90, data.count == 2, data[1] > 0 {
                    notes.insert(Int(status & 15) * 128 + Int(data[0]))
                }
            }
        }
        try MIDIPacketListBuilder.withPacketLists(for: events) { list in
            let status = MIDISend(port, destination, list)
            if status != noErr { throw MIDIConnectionError.system("отправка MIDI", status) }
        }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        if isValid { MIDIFlushOutput(destination) }
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard isValid else { return }
        MIDIFlushOutput(destination)
        let releases = notes.sorted().map { key in
            TimedMIDIEvent(hostTime: 0, bytes: [0x80 | UInt8(key / 128), UInt8(key % 128), 0])
        }
        try? MIDIPacketListBuilder.withPacketLists(for: releases) { list in
            let status = MIDISend(port, destination, list)
            if status != noErr { throw MIDIConnectionError.system("отключение MIDI", status) }
        }
        isValid = false
        notes.removeAll()
    }
}

/// Packs many timed events into as few `MIDIPacketList`s as possible.
/// Events sharing a timestamp share a packet up to `maximumPacketSize`;
/// SysEx always gets its own packet; a list never exceeds CoreMIDI's 64 KB.
enum MIDIPacketListBuilder {
    static let maximumPacketSize = 1024
    static let maximumListSize = 65536
    private static let listHeaderSize = MemoryLayout<MIDIPacketList>.offset(of: \.packet) ?? 4
    private static let packetHeaderSize = MemoryLayout<MIDIPacket>.offset(of: \.data) ?? 10

    struct Packet: Equatable {
        var hostTime: UInt64
        var bytes: [UInt8]
        var isSysEx: Bool { bytes.first == 0xf0 }
    }

    /// Bytes a packet occupies in a list, including the 4-byte alignment `MIDIPacketNext` applies on ARM.
    static func storageSize(ofPacketWith count: Int) -> Int { (packetHeaderSize + count + 3) & ~3 }

    static func packetLists(for events: [TimedMIDIEvent]) throws -> [[Packet]] {
        for event in events where event.bytes.isEmpty || event.bytes.count > maximumPacketSize {
            throw ProtocolError.unsupported("outgoing packet size")
        }
        let ordered = events.enumerated().sorted { ($0.element.hostTime, $0.offset) < ($1.element.hostTime, $1.offset) }
        var packets: [Packet] = []
        for (_, event) in ordered {
            if var last = packets.last, last.hostTime == event.hostTime, !last.isSysEx, event.bytes.first != 0xf0,
               last.bytes.count + event.bytes.count <= maximumPacketSize {
                last.bytes += event.bytes
                packets[packets.count - 1] = last
            } else {
                packets.append(Packet(hostTime: event.hostTime, bytes: event.bytes))
            }
        }
        var lists: [[Packet]] = []
        var current: [Packet] = []
        var size = listHeaderSize
        for packet in packets {
            let packetSize = storageSize(ofPacketWith: packet.bytes.count)
            // MIDIPacketListAdd merges equal-time non-SysEx packets; a separate list keeps them apart.
            let wouldMerge = current.last.map { $0.hostTime == packet.hostTime } ?? false
            if !current.isEmpty, wouldMerge || size + packetSize > maximumListSize {
                lists.append(current)
                current = []
                size = listHeaderSize
            }
            current.append(packet)
            size += packetSize
        }
        if !current.isEmpty { lists.append(current) }
        return lists
    }

    static func withPacketLists(for events: [TimedMIDIEvent], _ body: (UnsafePointer<MIDIPacketList>) throws -> Void) throws {
        for packets in try packetLists(for: events) {
            let capacity = max(MemoryLayout<MIDIPacketList>.size,
                               packets.reduce(listHeaderSize) { $0 + storageSize(ofPacketWith: $1.bytes.count) } + 4)
            let memory = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
            defer { memory.deallocate() }
            let list = memory.bindMemory(to: MIDIPacketList.self, capacity: 1)
            var current: UnsafeMutablePointer<MIDIPacket>? = MIDIPacketListInit(list)
            for packet in packets {
                current = packet.bytes.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress, let previous = current else { return nil }
                    return MIDIPacketListAdd(list, capacity, previous, packet.hostTime, buffer.count, base)
                }
                if current == nil { throw ProtocolError.unsupported("MIDI packet list overflow") }
            }
            try body(list)
        }
    }
}
