import Foundation

public enum MIDIMessage: Equatable, Sendable {
    case sysEx([UInt8])
    case channel(status: UInt8, data: [UInt8])
    case realtime(UInt8)
    case system(status: UInt8, data: [UInt8])
}

/// Stateful across CoreMIDI packet boundaries; real-time bytes may occur inside SysEx.
public struct MIDIStreamDecoder: Sendable {
    private var sysex: [UInt8]?
    private var status: UInt8?
    private var data: [UInt8] = []
    private let maximumSysExSize = 2_000_000
    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []
        for byte in bytes {
            if byte >= 0xf8 { messages.append(.realtime(byte)); continue }
            if byte == 0xf0 { sysex = [byte]; status = nil; data = []; continue }
            if sysex != nil {
                // Mutate the stored Array directly. Copying it to a local var
                // before each append triggers copy-on-write for every byte of
                // a large dump, turning accumulation into quadratic work.
                if byte == 0xf7 { sysex!.append(byte); messages.append(.sysEx(sysex!)); sysex = nil }
                else if byte < 0x80 && sysex!.count < maximumSysExSize { sysex!.append(byte) }
                else { sysex = nil }
                // A non-real-time status interrupts SysEx and starts a new message.
                if byte < 0x80 || byte == 0xf7 { continue }
            }
            if byte >= 0x80 {
                data = []
                if byte == 0xf6 { messages.append(.system(status: byte, data: [])); status = nil }
                else { status = [0xf4, 0xf5, 0xf7].contains(byte) ? nil : byte }
                continue
            }
            guard let active = status else { continue }
            data.append(byte)
            let count: Int
            if active < 0xf0 { count = [0xc0, 0xd0].contains(active & 0xf0) ? 1 : 2 }
            else { count = active == 0xf2 ? 2 : 1 }
            if data.count == count {
                messages.append(active < 0xf0 ? .channel(status: active, data: data) : .system(status: active, data: data))
                data = []
                if active >= 0xf0 { status = nil }
            }
        }
        return messages
    }
}

public struct ParameterEvent: Equatable, Sendable {
    public let channel: Int
    public let nrpn: Int?
    public let cc: Int?
    public let value: Int
    public let resolution: Int
}

public struct NRPNDecoder: Sendable {
    private struct State: Sendable {
        var parameterMSB: Int?
        var parameterLSB: Int?
        var valueMSB: Int?
    }
    private var states = Array(repeating: State(), count: 16)
    public init() {}

    public mutating func receive(channel: Int, cc: Int, value: Int) -> ParameterEvent? {
        guard (0..<16).contains(channel), (0..<128).contains(cc), (0..<128).contains(value) else { return nil }
        switch cc {
        case 99: states[channel].parameterMSB = value; states[channel].valueMSB = nil
        case 98: states[channel].parameterLSB = value; states[channel].valueMSB = nil
        case 100, 101: states[channel] = State() // RPN selection invalidates NRPN context.
        case 6:
            states[channel].valueMSB = value
            if let msb = states[channel].parameterMSB, let lsb = states[channel].parameterLSB,
               msb != 127 || lsb != 127 {
                return ParameterEvent(channel: channel, nrpn: msb * 128 + lsb, cc: nil, value: value * 128, resolution: 16383)
            }
        case 38:
            if let msb = states[channel].parameterMSB, let lsb = states[channel].parameterLSB,
               let valueMSB = states[channel].valueMSB, msb != 127 || lsb != 127 {
                return ParameterEvent(channel: channel, nrpn: msb * 128 + lsb, cc: nil, value: valueMSB * 128 + value, resolution: 16383)
            }
        default: return ParameterEvent(channel: channel, nrpn: nil, cc: cc, value: value, resolution: 127)
        }
        return nil
    }
}

public enum MIDIBytes {
    public static func cc(channel: Int, controller: Int, value: Int) throws -> [UInt8] {
        guard (0..<16).contains(channel), (0..<128).contains(controller), (0..<128).contains(value) else {
            throw ProtocolError.malformed("MIDI CC range")
        }
        return [0xb0 | UInt8(channel), UInt8(controller), UInt8(value)]
    }
    public static func nrpn(channel: Int, parameter: Int, value: Int) throws -> [UInt8] {
        guard (0...16383).contains(parameter), (0...16383).contains(value) else { throw ProtocolError.malformed("NRPN range") }
        return try cc(channel: channel, controller: 99, value: parameter >> 7)
            + cc(channel: channel, controller: 98, value: parameter & 127)
            + cc(channel: channel, controller: 6, value: value >> 7)
            + cc(channel: channel, controller: 38, value: value & 127)
    }
    public static func note(channel: Int, number: Int, velocity: Int, on: Bool) throws -> [UInt8] {
        guard (0..<16).contains(channel), (0..<128).contains(number), (0..<128).contains(velocity) else { throw ProtocolError.malformed("note range") }
        return [(on ? 0x90 : 0x80) | UInt8(channel), UInt8(number), UInt8(velocity)]
    }
}
