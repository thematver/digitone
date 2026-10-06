import Foundation

/// The SYN machine assigned to a Digitone II audio track (manual Appendix A).
/// It cannot be read or changed over MIDI; the app keeps the user's choice per track.
public enum DNMachine: String, CaseIterable, Codable, Sendable, Identifiable {
    case fmTone, fmDrum, wavetone, swarmer, midi
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fmTone: "FM TONE"
        case .fmDrum: "FM DRUM"
        case .wavetone: "WAVETONE"
        case .swarmer: "SWARMER"
        case .midi: "MIDI"
        }
    }
}

/// A parameter page as printed on the device. Track pages are addressed on the
/// track's MIDI channel; `isGlobal` pages on FX CONTROL CH (manual 13.4.3).
public enum DNPage: String, CaseIterable, Codable, Sendable, Identifiable {
    case trig, syn1, syn2, syn3, syn4, fltr1, fltr2, amp, fx, mod1, mod2, mod3, sequencer, track
    case delay, reverb, chorus, compressor, mixer, mixerRight
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .trig: "TRIG"
        case .syn1: "SYN1"
        case .syn2: "SYN2"
        case .syn3: "SYN3"
        case .syn4: "SYN4"
        case .fltr1: "FLTR1"
        case .fltr2: "FLTR2"
        case .amp: "AMP"
        case .fx: "FX"
        case .mod1: "MOD1"
        case .mod2: "MOD2"
        case .mod3: "MOD3"
        case .sequencer: "EUCLID"
        case .track: "TRACK"
        case .delay: "DELAY"
        case .reverb: "REVERB"
        case .chorus: "CHORUS"
        case .compressor: "COMP"
        case .mixer: "MIXER"
        case .mixerRight: "INPUT R"
        }
    }
    public var isGlobal: Bool { [.delay, .reverb, .chorus, .compressor, .mixer, .mixerRight].contains(self) }
}

/// How a coarse MIDI value 0...127 is shown, matching the device display where known.
public enum DNValueFormat: Hashable, Sendable {
    /// The raw value (or `offset + raw`) within a range, e.g. 0...127 or 1...128.
    case number(ClosedRange<Int>, offset: Int = 0)
    /// Stored 0...127, shown -64...+63.
    case bipolar
    case toggle
    /// Value index → device label (waveforms, modes, ratios…). Values past the end clamp to the last label.
    case options([String])
    /// Linear display mapping of 0...127 onto `min...max` with a unit.
    case scaled(min: Double, max: Double, decimals: Int, unit: String)
}

public struct DNParameter: Identifiable, Hashable, Sendable {
    /// Stable key, unique across the whole catalog, e.g. "fmTone.syn1.algo", "fltr1.freq", "delay.time".
    public let id: String
    public let page: DNPage
    /// Knob position on the page: 0...7 = A...H.
    public let slot: Int
    /// Short label as on the device screen, e.g. "ALGO".
    public let label: String
    /// Full name, e.g. "Algorithm".
    public let name: String
    /// CC number (coarse 7-bit) or nil when the parameter has no CC.
    public let cc: Int?
    /// NRPN number (MSB × 128 + LSB), or nil when none is published.
    public let nrpn: Int?
    public let format: DNValueFormat
    /// Default coarse value 0...127 (64 for bipolar when unknown).
    public let defaultValue: Int
    /// True when the device resolves more than 7 bits (send NRPN with LSB).
    public let isHighResolution: Bool

    public init(id: String, page: DNPage, slot: Int, label: String, name: String, cc: Int?, nrpn: Int?,
                format: DNValueFormat = .number(0...127), defaultValue: Int = 0, isHighResolution: Bool = false) {
        self.id = id
        self.page = page
        self.slot = slot
        self.label = label
        self.name = name
        self.cc = cc
        self.nrpn = nrpn
        self.format = format
        self.defaultValue = defaultValue
        self.isHighResolution = isHighResolution
    }

    public var knobLetter: String { String(UnicodeScalar(65 + slot)!) }
}

/// The device's MIDI CONFIG → CHANNELS settings as the app assumes them.
public struct DNChannelMap: Codable, Hashable, Sendable {
    /// Track 0...15 → MIDI channel 0...15; nil = OFF.
    public var trackChannels: [Int?]
    public var fxControlChannel: Int?
    public var autoChannel: Int
    /// nil = AUTO (uses `autoChannel`).
    public var programChangeChannel: Int?

    public init(trackChannels: [Int?], fxControlChannel: Int?, autoChannel: Int, programChangeChannel: Int?) {
        self.trackChannels = trackChannels
        self.fxControlChannel = fxControlChannel
        self.autoChannel = autoChannel
        self.programChangeChannel = programChangeChannel
    }

    public func channel(forTrack track: Int) -> Int? {
        trackChannels.indices.contains(track) ? trackChannels[track] : nil
    }

    public var effectiveProgramChangeChannel: Int { programChangeChannel ?? autoChannel }
}

/// Every MIDI-addressable Digitone II parameter (manual Appendix A and C).
///
/// CONTRACT: the public API is stable. Data is filled from the OS 1.12 manual;
/// see docs/research/DN2_PARAMETERS.md for sources and uncertainties.
public enum HardwareCatalog {
    /// Pages shown for a track with `machine`, in device order.
    public static func pages(for machine: DNMachine) -> [DNPage] {
        CatalogData.pages(for: machine)
    }

    /// The global pages addressed on FX CONTROL CH.
    public static var globalPages: [DNPage] { DNPage.allCases.filter(\.isGlobal) }

    /// Parameters on `page`, ordered by slot (A...H). Machine-independent pages ignore `machine`.
    public static func parameters(on page: DNPage, machine: DNMachine) -> [DNParameter] {
        CatalogData.parameters(on: page, machine: machine).sorted { $0.slot < $1.slot }
    }

    /// All parameters reachable for a track with `machine` (all its pages).
    public static func parameters(for machine: DNMachine) -> [DNParameter] {
        pages(for: machine).flatMap { parameters(on: $0, machine: machine) }
    }

    /// Resolves an incoming CC/NRPN to a parameter. `global` selects FX CONTROL CH pages.
    public static func match(cc: Int?, nrpn: Int?, machine: DNMachine, global: Bool) -> DNParameter? {
        let candidates = global ? globalPages.flatMap { parameters(on: $0, machine: machine) } : parameters(for: machine)
        if let nrpn, let found = candidates.first(where: { $0.nrpn == nrpn }) { return found }
        if let cc, let found = candidates.first(where: { $0.cc == cc }) { return found }
        return nil
    }

    public static func parameter(id: String) -> DNParameter? {
        DNMachine.allCases.lazy.compactMap { machine in
            (pages(for: machine) + globalPages).lazy.flatMap { parameters(on: $0, machine: machine) }.first { $0.id == id }
        }.first
    }

    /// The factory MIDI channel configuration of the Digitone II.
    public static var factoryChannels: DNChannelMap { CatalogData.factoryChannels }

    /// Device-style text for a coarse value, e.g. "-12", "ON", "SAW", "1.50".
    public static func display(_ value: Int, format: DNValueFormat) -> String {
        let raw = min(127, max(0, value))
        switch format {
        case .number(let range, let offset):
            return String(min(range.upperBound, max(range.lowerBound, raw + offset)))
        case .bipolar:
            let shown = raw - 64
            return shown > 0 ? "+\(shown)" : String(shown)
        case .toggle:
            return raw == 0 ? "OFF" : "ON"
        case .options(let labels):
            guard !labels.isEmpty else { return String(raw) }
            return labels[min(raw, labels.count - 1)]
        case .scaled(let low, let high, let decimals, let unit):
            let shown = low + (high - low) * Double(raw) / 127
            let text = String(format: "%.\(max(0, decimals))f", shown)
            return unit.isEmpty ? text : "\(text) \(unit)"
        }
    }
}
