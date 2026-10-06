import Foundation
import DigitoneCore
import DigitoneMIDI

// Pure encoding, routing and rate limiting behind the device control surface.
// Nothing here touches CoreMIDI, so all of it is unit-testable.

/// Where a value shown on screen came from. A missing value is unknown.
enum ControlInputRouting: String, CaseIterable, Identifiable {
    case autoChannel = "AUTO CH"
    case trackChannel = "TRK CH"
    var id: Self { self }
}

enum ControlOrigin: Equatable, Sendable { case draft, sent, received }

/// A value together with its origin.
struct Observed<Value: Equatable>: Equatable {
    var value: Value
    var origin: ControlOrigin
}

/// A parameter value as a 14-bit number: coarse (MSB) × 128 + fine (LSB).
typealias ControlValue = Observed<Int>

/// Track parameters live per track; DELAY/REVERB/CHORUS/COMP/MIXER are global (FX CONTROL CH).
enum ControlScope: Hashable, Sendable {
    case track(Int)
    case global
}

struct ControlKey: Hashable, Sendable {
    let scope: ControlScope
    let id: String
}

/// One outgoing MIDI message.
enum ControlMessage: Equatable, Sendable {
    case cc(channel: Int, controller: Int, value: Int)
    case nrpn(channel: Int, parameter: Int, value: Int)
    case programChange(channel: Int, program: Int)
    case start
    case stop

    var bytes: [UInt8] {
        func status(_ kind: UInt8, _ channel: Int) -> UInt8 { kind | UInt8(min(15, max(0, channel))) }
        func data(_ value: Int) -> UInt8 { UInt8(min(127, max(0, value))) }
        switch self {
        case .cc(let channel, let controller, let value):
            return [status(0xb0, channel), data(controller), data(value)]
        case .nrpn(let channel, let parameter, let value):
            let number = min(16383, max(0, parameter)), amount = min(16383, max(0, value))
            let head = status(0xb0, channel)
            return [head, 99, UInt8(number >> 7), head, 98, UInt8(number & 127),
                    head, 6, UInt8(amount >> 7), head, 38, UInt8(amount & 127)]
        case .programChange(let channel, let program):
            return [status(0xc0, channel), data(program)]
        case .start: return [0xfa]
        case .stop: return [0xfc]
        }
    }
}

extension DNValueFormat {
    /// The coarse values (0...127) the device uses for this format.
    var rawRange: ClosedRange<Int> {
        switch self {
        case .number(let range, let offset):
            let low = min(127, max(0, range.lowerBound - offset))
            return low...min(127, max(low, range.upperBound - offset))
        case .options(let labels) where !labels.isEmpty:
            return 0...min(127, labels.count - 1)
        default:
            return 0...127
        }
    }

    var isBipolar: Bool { if case .bipolar = self { true } else { false } }
    var isToggle: Bool { if case .toggle = self { true } else { false } }
}

extension DNParameter {
    var rawRange: ClosedRange<Int> { format.rawRange }
    var defaultValue14: Int { min(rawRange.upperBound, max(rawRange.lowerBound, defaultValue)) << 7 }
    /// Coarse value of a 14-bit value.
    static func coarse(_ value14: Int) -> Int { min(127, max(0, value14 >> 7)) }

    /// 0...1 position of a 14-bit value within this parameter's range.
    func fraction(of value14: Int) -> Double {
        let range = rawRange
        guard range.upperBound > range.lowerBound else { return 0 }
        let position = isHighResolution ? Double(value14) / 128 : Double(value14 >> 7)
        return min(1, max(0, (position - Double(range.lowerBound)) / Double(range.upperBound - range.lowerBound)))
    }

    /// The 14-bit value at a 0...1 position, rounded to what the parameter resolves.
    func value14(atFraction fraction: Double) -> Int {
        let range = rawRange
        let position = Double(range.lowerBound) + min(1, max(0, fraction)) * Double(range.upperBound - range.lowerBound)
        let value14 = isHighResolution ? Int((position * 128).rounded()) : Int(position.rounded()) << 7
        return ControlEncoding.clamp(value14, for: self)
    }

    /// Device-formatted text for a 14-bit value; fine steps of high-resolution parameters show as decimals.
    func display(_ value14: Int) -> String {
        let coarse = Self.coarse(value14), fine = value14 & 127
        guard isHighResolution, fine != 0 else { return HardwareCatalog.display(coarse, format: format) }
        let position = min(127, Double(value14) / 128)
        switch format {
        case .number(let range, let offset):
            let shown = min(Double(range.upperBound), max(Double(range.lowerBound), position + Double(offset)))
            return String(format: "%.2f", shown)
        case .bipolar:
            let shown = position - 64
            return String(format: shown > 0 ? "+%.2f" : "%.2f", shown)
        case .scaled(let low, let high, let decimals, let unit):
            let text = String(format: "%.\(max(0, decimals))f", low + (high - low) * position / 127)
            return unit.isEmpty ? text : "\(text) \(unit)"
        default:
            return HardwareCatalog.display(coarse, format: format)
        }
    }
}

enum ControlEncoding {
    static let maximum = 16383

    /// Clamps a 14-bit value to the parameter's range. Values of 7-bit parameters lose their fine bits.
    static func clamp(_ value14: Int, for parameter: DNParameter) -> Int {
        let range = parameter.rawRange
        let low = range.lowerBound << 7
        let high = parameter.isHighResolution ? (range.upperBound << 7) | 127 : range.upperBound << 7
        let clamped = min(high, max(low, value14))
        return parameter.isHighResolution ? clamped : (clamped >> 7) << 7
    }

    /// NRPN when the parameter has one (MSB = coarse, LSB = fine for high-resolution
    /// parameters, else 0); CC with the coarse value when it has no NRPN.
    static func message(for parameter: DNParameter, value14: Int, channel: Int) -> ControlMessage? {
        guard (0..<16).contains(channel) else { return nil }
        let value = clamp(value14, for: parameter)
        if let nrpn = parameter.nrpn { return .nrpn(channel: channel, parameter: nrpn, value: value) }
        if let cc = parameter.cc { return .cc(channel: channel, controller: cc, value: value >> 7) }
        return nil
    }

    /// Track mute as the Digitone expects it: CC 94, 127 = muted, 0 = playing.
    static let muteController = 94
    static func mute(_ muted: Bool, channel: Int) -> ControlMessage {
        .cc(channel: channel, controller: muteController, value: muted ? 127 : 0)
    }

    /// Program change number for bank A...H (0...7) and pattern 1...16 (0...15).
    static func program(bank: Int, pattern: Int) -> Int {
        min(7, max(0, bank)) * 16 + min(15, max(0, pattern))
    }

    /// 14-bit value of an incoming CC (7-bit) or NRPN (14-bit) event.
    static func value14(of event: ParameterEvent) -> Int {
        min(maximum, max(0, event.resolution == 16383 ? event.value : event.value << 7))
    }
}

/// The parameter data the surface works with. Production uses `HardwareCatalog`;
/// tests and previews supply fixed data with the same lookup rules.
struct ControlCatalog: Sendable {
    var pages: @Sendable (DNMachine) -> [DNPage]
    var parameters: @Sendable (DNPage, DNMachine) -> [DNParameter]
    var match: @Sendable (_ cc: Int?, _ nrpn: Int?, _ machine: DNMachine, _ global: Bool) -> DNParameter?

    static let hardware = ControlCatalog(
        pages: { HardwareCatalog.pages(for: $0) },
        parameters: { HardwareCatalog.parameters(on: $0, machine: $1) },
        match: { HardwareCatalog.match(cc: $0, nrpn: $1, machine: $2, global: $3) })

    /// A catalog over fixed parameters. `machineParameters` holds machine-dependent (SYN) pages.
    static func fixed(pages: @escaping @Sendable (DNMachine) -> [DNPage],
                      shared: [DNParameter],
                      machineParameters: [DNMachine: [DNParameter]] = [:]) -> ControlCatalog {
        let lookup: @Sendable (DNPage, DNMachine) -> [DNParameter] = { page, machine in
            ((machineParameters[machine] ?? []) + shared).filter { $0.page == page }.sorted { $0.slot < $1.slot }
        }
        return ControlCatalog(pages: pages, parameters: lookup, match: { cc, nrpn, machine, global in
            let candidates = global
                ? DNPage.allCases.filter(\.isGlobal).flatMap { lookup($0, machine) }
                : pages(machine).flatMap { lookup($0, machine) }
            if let nrpn, let found = candidates.first(where: { $0.nrpn == nrpn }) { return found }
            if let cc, let found = candidates.first(where: { $0.cc == cc }) { return found }
            return nil
        })
    }
}

enum ControlRouting {
    /// The MIDI channel a scope is addressed on; nil when it is OFF in the channel map.
    static func channel(for scope: ControlScope, in map: DNChannelMap) -> Int? {
        switch scope {
        case .track(let track): map.channel(forTrack: track)
        case .global: map.fxControlChannel
        }
    }

    /// Candidate scopes for a message arriving on `channel`, most specific first:
    /// FX CONTROL CH, then AUTO CHANNEL → selected track when output uses AUTO,
    /// then tracks on that channel (the selected one first).
    static func scopes(forIncoming channel: Int, map: DNChannelMap, selectedTrack: Int, preferAuto: Bool = true) -> [ControlScope] {
        var result: [ControlScope] = []
        if map.fxControlChannel == channel { result.append(.global) }
        if preferAuto, map.autoChannel == channel { result.append(.track(selectedTrack)) }
        let tracks = map.trackChannels.indices.filter { map.trackChannels[$0] == channel }
        if tracks.contains(selectedTrack), !result.contains(.track(selectedTrack)) { result.append(.track(selectedTrack)) }
        result += tracks.filter { $0 != selectedTrack }.map { .track($0) }
        return result
    }

    /// Resolves an incoming CC/NRPN to the value it changes, or nil when it is not a known parameter.
    static func resolve(_ event: ParameterEvent, map: DNChannelMap, machines: [DNMachine], selectedTrack: Int,
                        catalog: ControlCatalog, preferAuto: Bool = true) -> (key: ControlKey, parameter: DNParameter, value: Int)? {
        let value = ControlEncoding.value14(of: event)
        for scope in scopes(forIncoming: event.channel, map: map, selectedTrack: selectedTrack, preferAuto: preferAuto) {
            switch scope {
            case .global:
                let machine = machines.indices.contains(selectedTrack) ? machines[selectedTrack] : .fmTone
                if let parameter = catalog.match(event.cc, event.nrpn, machine, true) {
                    return (ControlKey(scope: .global, id: parameter.id), parameter, value)
                }
            case .track(let track):
                let machine = machines.indices.contains(track) ? machines[track] : .fmTone
                if let parameter = catalog.match(event.cc, event.nrpn, machine, false) {
                    return (ControlKey(scope: scope, id: parameter.id), parameter, value)
                }
                let mute = ControlMute.parameter(machine: machine, catalog: catalog)
                if (event.cc != nil && event.cc == mute.cc) || (event.nrpn != nil && event.nrpn == mute.nrpn) {
                    return (ControlKey(scope: scope, id: mute.id), mute, value)
                }
            }
        }
        return nil
    }
}

/// The TRACK page's mute: the catalog entry on CC 94 when present, otherwise a built-in one.
enum ControlMute {
    static let fallback = DNParameter(id: "track.mute", page: .track, slot: 0, label: "MUTE", name: "Mute",
                                      cc: ControlEncoding.muteController, nrpn: 128 + 108, format: .toggle)

    static func parameter(machine: DNMachine, catalog: ControlCatalog) -> DNParameter {
        catalog.parameters(.track, machine).first { $0.cc == ControlEncoding.muteController } ?? fallback
    }

    static func isMuted(_ value14: Int) -> Bool { value14 >> 7 >= 64 }
}

/// Limits sends per key to one per `interval`, keeping only the newest value
/// in between, so a fast knob drag never floods the device but its final value always arrives.
struct SendThrottle<Key: Hashable, Payload> {
    let interval: Double
    private var lastSent: [Key: Double] = [:]
    private(set) var pending: [Key: Payload] = [:]

    init(interval: Double) { self.interval = interval }

    /// The payload to send now, or nil when it was queued behind a recent send.
    mutating func offer(_ payload: Payload, for key: Key, at now: Double) -> Payload? {
        if let last = lastSent[key], now - last < interval {
            pending[key] = payload
            return nil
        }
        lastSent[key] = now
        pending[key] = nil
        return payload
    }

    /// Queued payloads whose interval has elapsed, removed from the queue.
    mutating func due(at now: Double) -> [(key: Key, payload: Payload)] {
        var result: [(key: Key, payload: Payload)] = []
        for (key, payload) in pending where now - (lastSent[key] ?? -.infinity) >= interval {
            result.append((key, payload))
        }
        for item in result { pending[item.key] = nil; lastSent[item.key] = now }
        return result
    }

    /// The queued value for `key`, released immediately (end of a gesture).
    mutating func flush(_ key: Key, at now: Double) -> Payload? {
        guard let payload = pending.removeValue(forKey: key) else { return nil }
        lastSent[key] = now
        return payload
    }

    mutating func flushAll(at now: Double) -> [(key: Key, payload: Payload)] {
        let result = pending.map { (key: $0.key, payload: $0.value) }
        for item in result { lastSent[item.key] = now }
        pending.removeAll()
        return result
    }

    /// When the earliest queued payload becomes due.
    var nextDue: Double? {
        pending.keys.compactMap { key in lastSent[key].map { $0 + interval } }.min()
    }
}

/// Where the surface sends MIDI. Production wraps the connected `StudioModel`; tests record.
@MainActor
protocol ControlOutput: AnyObject {
    var isAvailable: Bool { get }
    func send(_ message: ControlMessage) throws
    func noteOn(channel: Int, note: Int, velocity: Int)
    func noteOff(channel: Int, note: Int)
}

@MainActor
final class StudioControlOutput: ControlOutput {
    private weak var studio: StudioModel?
    init(studio: StudioModel) { self.studio = studio }

    var isAvailable: Bool { studio?.midiSession != nil }

    func send(_ message: ControlMessage) throws {
        guard let session = studio?.midiSession else { throw MIDIConnectionError.disconnected }
        try session.transport.send(message.bytes)
    }

    func noteOn(channel: Int, note: Int, velocity: Int) { studio?.noteOn(channel: channel, note: note, velocity: velocity) }
    func noteOff(channel: Int, note: Int) { studio?.noteOff(channel: channel, note: note) }
}

/// Accepts everything and sends nothing: snapshot scenes render the "connected" look with it.
@MainActor
final class SilentControlOutput: ControlOutput {
    var isAvailable: Bool
    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }
    func send(_ message: ControlMessage) throws {}
    func noteOn(channel: Int, note: Int, velocity: Int) {}
    func noteOff(channel: Int, note: Int) {}
}
