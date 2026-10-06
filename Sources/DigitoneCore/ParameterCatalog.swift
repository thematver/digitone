import Foundation

/// A user-supplied label for the machine already assigned on the Digitone.
/// Choosing a label never changes the machine on the instrument.
public enum SynthMachine: String, Codable, CaseIterable, Identifiable, Sendable {
    case fmTone, fmDrum, wavetone, swarmer

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fmTone: return "FM Tone"
        case .fmDrum: return "FM Drum"
        case .wavetone: return "Wavetone"
        case .swarmer: return "Swarmer"
        }
    }
}

/// Values in this first editor are the coarse MIDI value 0...127, not a
/// calibrated frequency, time, operator ratio or the hardware display value.
public struct ParameterDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let section: String
    public let cc: Int?
    public let nrpn: Int
    public let detail: String

    public init(id: String, title: String, section: String, cc: Int?, nrpn: Int, detail: String) {
        self.id = id
        self.title = title
        self.section = section
        self.cc = cc
        self.nrpn = nrpn
        self.detail = detail
    }
}

/// Source: Elektron Digitone II User Manual OS 1.10C, Appendix A and C.
/// https://www.elektron.se/wp-content/uploads/2025/07/Digitone-2-User-Manual_ENG_OS1.10C_250708.pdf
/// SYN controls address page positions; their meanings depend on the machine
/// selected on the hardware. FILTER F/G also depend on the hardware FLTR
/// machine, which this prototype does not read or change.
public enum ParameterCatalog {
    public static func parameters(for machine: SynthMachine) -> [ParameterDefinition] {
        let names: [String]
        switch machine {
        case .fmTone:
            names = ["Algorithm", "Ratio C", "Ratio A", "Ratio B", "Harmonics", "Detune", "Feedback", "Mix"]
        case .fmDrum:
            names = ["Tune", "Sweep time", "Sweep depth", "Algorithm", "Operator C wave", "Operator AB wave", "Feedback", "Fold"]
        case .wavetone:
            names = ["Osc 1 tune", "Osc 1 waveform", "Osc 1 phase distortion", "Osc 1 level", "Osc 2 tune", "Osc 2 waveform", "Osc 2 phase distortion", "Osc 2 level"]
        case .swarmer:
            names = ["Tune", "Swarm waveform", "Detune", "Mix", "Main octave", "Main waveform", "Animation", "Noise modulation"]
        }
        let source = names.enumerated().map { index, name in
            ParameterDefinition(id: "syn.1.\(String(UnicodeScalar(97 + index)!))", title: name,
                                section: "SYN · \(machine.title)", cc: 40 + index, nrpn: 128 + 73 + index,
                                detail: "SYN 1 · ручка \(String(UnicodeScalar(65 + index)!)). Значение MIDI 0–127; выбранный движок должен совпадать с прибором.")
        }
        let legacy = source + common
        let hardware = HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!)
        let additional = hardware.filter { hardware in
            !legacy.contains { definition in
                hardware.nrpn.map { $0 == definition.nrpn } ?? (hardware.cc == definition.cc)
            }
        }.map { hardware in
            ParameterDefinition(id: hardware.id, title: hardware.name, section: hardware.page.title,
                                cc: hardware.cc, nrpn: hardware.nrpn ?? 0,
                                detail: "\(hardware.page.title) · ручка \(hardware.knobLetter). Грубое значение MIDI 0–127.")
        }
        return legacy + additional
    }

    /// Keeps legacy snapshot IDs stable while the control surface uses the complete hardware catalog.
    public static func definition(for hardware: DNParameter, machine: SynthMachine) -> ParameterDefinition? {
        guard !hardware.page.isGlobal else { return nil }
        return parameters(for: machine).first { definition in
            hardware.nrpn.map { $0 == definition.nrpn } ?? (hardware.cc == definition.cc)
        }
    }

    public static func hardwareParameter(for definition: ParameterDefinition, machine: SynthMachine) -> DNParameter? {
        HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!).first { hardware in
            hardware.nrpn.map { $0 == definition.nrpn } ?? (hardware.cc == definition.cc)
        }
    }

    private static func control(_ id: String, _ title: String, _ section: String, _ cc: Int?, _ lsb: Int,
                                detail: String = "Значение MIDI 0–127; единицы и шкалу показывает прибор.") -> ParameterDefinition {
        ParameterDefinition(id: id, title: title, section: section, cc: cc, nrpn: 128 + lsb, detail: detail)
    }

    public static let common: [ParameterDefinition] = [
        control("filter.frequency", "Frequency", "FILTER", 16, 20),
        control("filter.controlF", "FLTR · F", "FILTER", 17, 21, detail: "Назначение ручки F зависит от FLTR machine на приборе. Значение MIDI 0–127."),
        control("filter.controlG", "FLTR · G", "FILTER", 18, 22, detail: "Назначение ручки G зависит от FLTR machine на приборе. Значение MIDI 0–127."),
        control("filter.envelopeDepth", "Envelope depth", "FILTER", 24, 26),
        control("filter.attack", "Attack", "FILTER envelope", 20, 16),
        control("filter.decay", "Decay", "FILTER envelope", 21, 17),
        control("filter.sustain", "Sustain", "FILTER envelope", 22, 18),
        control("filter.release", "Release", "FILTER envelope", 23, 19),
        control("filter.delay", "Envelope delay", "FILTER envelope", 19, 23),
        control("filter.keyTracking", "Key tracking", "FILTER", 26, 69),
        control("filter.base", "Base", "FILTER", 27, 24),
        control("filter.width", "Width", "FILTER", 28, 25),
        control("amp.attack", "Attack", "AMP", 84, 30),
        control("amp.hold", "Hold", "AMP", 85, 31),
        control("amp.decay", "Decay", "AMP", 86, 32),
        // The manual prints CC 86 for both Decay and Sustain. Use the unique
        // published NRPN instead of guessing a corrected CC value.
        control("amp.sustain", "Sustain", "AMP", nil, 33, detail: "Управление через NRPN. Значение MIDI 0–127; CC в таблице руководства неоднозначен."),
        control("amp.release", "Release", "AMP", 88, 34),
        control("amp.pan", "Pan", "AMP", 89, 38),
        control("amp.volume", "Volume", "AMP", 90, 39),
        control("fx.chorusSend", "Chorus send", "FX sends", 29, 35),
        control("fx.delaySend", "Delay send", "FX sends", 30, 36),
        control("fx.reverbSend", "Reverb send", "FX sends", 31, 37),
        control("track.level", "Track level", "TRACK", 95, 110)
    ]
}
