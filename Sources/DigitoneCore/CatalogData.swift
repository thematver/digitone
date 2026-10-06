import Foundation

/// Parameter data behind `HardwareCatalog`, transcribed from the Digitone II OS 1.12 manual
/// (chapters 11–12, Appendix A, C and D). Sources, decisions and open questions live in
/// docs/research/DN2_PARAMETERS.md; docs/research/dn2-parameters.json is the machine-readable twin
/// that HardwareCatalogTests checks this data against.
///
/// Rules:
/// - Only MIDI-addressable knobs are listed. A device knob without CC/NRPN (PROB, FILL, COND, retrigs,
///   BW.RT, SEL1–16) leaves its slot empty; a page without any such knob is not offered.
/// - `slot` is the knob position on the device screen (A–D top row, E–H bottom row).
/// - Parameters the device shows outside the eight knobs are filed on a free knob of the closest page:
///   PTIM/PORT (TRIG page 2 knobs G/H) on TRIG, the LEVEL/DATA volumes of DELAY/REVERB/CHORUS/MIXER,
///   AMP HOLD (AHD layout only) and Pattern Mute on TRACK, master overdrive on MIXER.
/// - EUCLID exposes the SEQUENCER menu; INPUT R exposes EXTERNAL MIXER page 6 (DUAL ON).
enum CatalogData {
    static func pages(for machine: DNMachine) -> [DNPage] {
        DNPage.allCases.filter { trackPages[machine]?[$0] != nil }
    }

    static func parameters(on page: DNPage, machine: DNMachine) -> [DNParameter] {
        page.isGlobal ? globalPages[page] ?? [] : trackPages[machine]?[page] ?? []
    }

    /// TRACK 1–16 on channels 1–16 is stated in the manual (8.4). AUTO CHANNEL 10 is what the
    /// user's unit reports; FX CONTROL CH (OFF) and PROGRAM CHG IN CH (AUTO) are not stated and assumed.
    static let factoryChannels = DNChannelMap(trackChannels: (0..<16).map { $0 }, fxControlChannel: nil,
                                              autoChannel: 9, programChangeChannel: nil)

    /// NRPN number from the MSB/LSB columns of Appendix C.
    static func n(_ msb: Int, _ lsb: Int) -> Int { msb * 128 + lsb }

    /// Every track parameter of `machine`, in page order.
    static func trackParameters(_ machine: DNMachine) -> [DNParameter] {
        switch machine {
        case .fmTone: trig + fmTone + filter + amp + fx + mod(.fmTone, syn: fmTone) + sequencer + track
        case .fmDrum: trig + fmDrum + filter + amp + fx + mod(.fmDrum, syn: fmDrum) + sequencer + track
        case .wavetone: trig + wavetone + filter + amp + fx + mod(.wavetone, syn: wavetone) + sequencer + track
        case .swarmer: trig + swarmer + filter + amp + fx + mod(.swarmer, syn: swarmer) + sequencer + track
        case .midi: midiTrig + midi + midiValues + mod(.midi, syn: midi) + sequencer + midiTrack
        }
    }

    /// Every global parameter (FX CONTROL CH), in page order.
    static var globalParameters: [DNParameter] { delay + reverb + chorus + compressor + mixer + mixerRight }

    private static let trackPages: [DNMachine: [DNPage: [DNParameter]]] = Dictionary(
        uniqueKeysWithValues: DNMachine.allCases.map { ($0, Dictionary(grouping: trackParameters($0), by: \.page)) })

    private static let globalPages: [DNPage: [DNParameter]] = Dictionary(grouping: globalParameters, by: \.page)

    /// MOD pages: LFO 1–3 for audio machines, LFO 1–2 for MIDI (11.9–11.11), with this machine's DEST list.
    private static func mod(_ machine: DNMachine, syn: [DNParameter]) -> [DNParameter] {
        let lfos = machine == .midi ? [mod1, mod2] : [mod1, mod2, mod3]
        return lfos.enumerated().flatMap { index, lfo in lfo + [destination(machine, lfo: index + 1, syn: syn)] }
    }

    /// DEST knob (D) of LFO `lfo` (C.8; LFO 3 has no CC). Machine dependent because the list names
    /// the machine's SYN knobs, so the id carries the machine: "fmTone.mod1.dest".
    private static func destination(_ machine: DNMachine, lfo: Int, syn: [DNParameter]) -> DNParameter {
        let page: DNPage = [.mod1, .mod2, .mod3][lfo - 1]
        return DNParameter(id: "\(machine.rawValue).\(page.rawValue).dest", page: page, slot: 3, label: "DEST",
                           name: "Destination", cc: [105, 114, nil][lfo - 1], nrpn: n(1, [45, 53, 61][lfo - 1]),
                           format: .options(Labels.lfoDestinations(machine, lfo: lfo, syn: syn)))
    }

    // MARK: Track pages

    /// TRIG (11.2–11.3, C.2): TRIG page 1 knobs plus PTIM/PORT from TRIG page 2, where they sit on G/H too.
    static let trig: [DNParameter] = [
        DNParameter(id: "trig.note", page: .trig, slot: 0, label: "NOTE", name: "Trig Note", cc: 3, nrpn: n(3, 0),
                    format: .options(Labels.notes), defaultValue: 60),
        DNParameter(id: "trig.vel", page: .trig, slot: 1, label: "VEL", name: "Trig Velocity", cc: 4, nrpn: n(3, 1), defaultValue: 100),
        DNParameter(id: "trig.len", page: .trig, slot: 2, label: "LEN", name: "Trig Length", cc: 5, nrpn: n(3, 2)),
        DNParameter(id: "trig.lfoTrig", page: .trig, slot: 4, label: "LFO.T", name: "LFO Trig", cc: 14, nrpn: nil, format: .toggle),
        DNParameter(id: "trig.fltTrig", page: .trig, slot: 5, label: "FLT.T", name: "Filter Trig", cc: 13, nrpn: nil, format: .toggle),
        DNParameter(id: "trig.portTime", page: .trig, slot: 6, label: "PTIM", name: "Portamento Time", cc: 9, nrpn: n(3, 6)),
        DNParameter(id: "trig.port", page: .trig, slot: 7, label: "PORT", name: "Portamento", cc: 65, nrpn: n(3, 7), format: .toggle)
    ]

    /// MIDI tracks: NOTE, VEL, LEN and LFO.T only (A.2.5).
    static var midiTrig: [DNParameter] { trig.filter { ["trig.note", "trig.vel", "trig.len", "trig.lfoTrig"].contains($0.id) } }

    /// FLTR pages 1–2 (11.5–11.6, A.3, C.4). Knobs F/G of page 1 depend on the FLTR machine, which
    /// MIDI cannot read; see the table in DN2_PARAMETERS.md. Page 2 knobs B/C are empty, G (BW.RT) has no address.
    static let filter: [DNParameter] = [
        DNParameter(id: "fltr1.atk", page: .fltr1, slot: 0, label: "ATK", name: "Attack Time", cc: 20, nrpn: n(1, 16)),
        DNParameter(id: "fltr1.dec", page: .fltr1, slot: 1, label: "DEC", name: "Decay Time", cc: 21, nrpn: n(1, 17)),
        DNParameter(id: "fltr1.sus", page: .fltr1, slot: 2, label: "SUS", name: "Sustain Level", cc: 22, nrpn: n(1, 18)),
        DNParameter(id: "fltr1.rel", page: .fltr1, slot: 3, label: "REL", name: "Release Time", cc: 23, nrpn: n(1, 19)),
        DNParameter(id: "fltr1.freq", page: .fltr1, slot: 4, label: "FREQ", name: "Frequency", cc: 16, nrpn: n(1, 20),
                    defaultValue: 127, isHighResolution: true),
        DNParameter(id: "fltr1.f", page: .fltr1, slot: 5, label: "F", name: "Filter knob F (RESO · FDBK · GAIN)", cc: 17, nrpn: n(1, 21)),
        DNParameter(id: "fltr1.g", page: .fltr1, slot: 6, label: "G", name: "Filter knob G (TYPE · LPF · Q)", cc: 18, nrpn: n(1, 22)),
        DNParameter(id: "fltr1.env", page: .fltr1, slot: 7, label: "ENV", name: "Env. Depth", cc: 24, nrpn: n(1, 26),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "fltr2.del", page: .fltr2, slot: 0, label: "DEL", name: "Env. Delay", cc: 19, nrpn: n(1, 23)),
        DNParameter(id: "fltr2.keyTrack", page: .fltr2, slot: 3, label: "KEY.T", name: "Key Tracking", cc: 26, nrpn: n(1, 69)),
        DNParameter(id: "fltr2.base", page: .fltr2, slot: 4, label: "BASE", name: "Base", cc: 27, nrpn: n(1, 24)),
        DNParameter(id: "fltr2.width", page: .fltr2, slot: 5, label: "WDTH", name: "Width", cc: 28, nrpn: n(1, 25), defaultValue: 127),
        DNParameter(id: "fltr2.reset", page: .fltr2, slot: 7, label: "RSET", name: "Env. Reset", cc: 25, nrpn: n(1, 68),
                    format: .toggle, defaultValue: 1)
    ]

    /// AMP (11.7, C.5) in the ADSR layout of the manual screenshot. HOLD (AHD only) lives on TRACK.
    static let amp: [DNParameter] = [
        DNParameter(id: "amp.atk", page: .amp, slot: 0, label: "ATK", name: "Attack Time", cc: 84, nrpn: n(1, 30)),
        DNParameter(id: "amp.dec", page: .amp, slot: 1, label: "DEC", name: "Decay Time", cc: 86, nrpn: n(1, 32)),
        DNParameter(id: "amp.sus", page: .amp, slot: 2, label: "SUS", name: "Sustain Level", cc: nil, nrpn: n(1, 33), defaultValue: 127),
        DNParameter(id: "amp.rel", page: .amp, slot: 3, label: "REL", name: "Release Time", cc: 88, nrpn: n(1, 34)),
        DNParameter(id: "amp.reset", page: .amp, slot: 4, label: "RSET", name: "Env. Reset", cc: 92, nrpn: n(1, 41),
                    format: .toggle, defaultValue: 1),
        DNParameter(id: "amp.mode", page: .amp, slot: 5, label: "MODE", name: "Envelope Mode", cc: 91, nrpn: n(1, 40),
                    format: .options(["AHD", "ADSR"])),
        DNParameter(id: "amp.pan", page: .amp, slot: 6, label: "PAN", name: "Pan", cc: 89, nrpn: n(1, 38), format: .bipolar, defaultValue: 64),
        DNParameter(id: "amp.vol", page: .amp, slot: 7, label: "VOL", name: "Volume", cc: 90, nrpn: n(1, 39), defaultValue: 100)
    ]

    /// FX (11.8, C.7). Empty on MIDI tracks.
    static let fx: [DNParameter] = [
        DNParameter(id: "fx.br", page: .fx, slot: 0, label: "BR", name: "Bit Reduction", cc: 78, nrpn: n(1, 5)),
        DNParameter(id: "fx.over", page: .fx, slot: 1, label: "OVER", name: "Overdrive", cc: 81, nrpn: n(1, 8)),
        DNParameter(id: "fx.srr", page: .fx, slot: 2, label: "SRR", name: "Sample Rate Reduction", cc: 79, nrpn: n(1, 6)),
        DNParameter(id: "fx.srrRouting", page: .fx, slot: 3, label: "SR.RT", name: "SRR Routing", cc: 80, nrpn: n(1, 7),
                    format: .options(Labels.prePost)),
        DNParameter(id: "fx.delay", page: .fx, slot: 4, label: "DEL", name: "Delay Send", cc: 30, nrpn: n(1, 36)),
        DNParameter(id: "fx.reverb", page: .fx, slot: 5, label: "REV", name: "Reverb Send", cc: 31, nrpn: n(1, 37)),
        DNParameter(id: "fx.chorus", page: .fx, slot: 6, label: "CHR", name: "Chorus Send", cc: 29, nrpn: n(1, 35)),
        DNParameter(id: "fx.odRouting", page: .fx, slot: 7, label: "OD.RT", name: "Overdrive Routing", cc: 82, nrpn: n(1, 9),
                    format: .options(Labels.prePost))
    ]

    /// LFO 1 (11.9, C.8) without DEST, which is machine dependent.
    static let mod1: [DNParameter] = [
        DNParameter(id: "mod1.spd", page: .mod1, slot: 0, label: "SPD", name: "Speed", cc: 102, nrpn: n(1, 42), format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod1.mult", page: .mod1, slot: 1, label: "MULT", name: "Multiplier", cc: 103, nrpn: n(1, 43),
                    format: .options(Labels.lfoMultiplier)),
        DNParameter(id: "mod1.fade", page: .mod1, slot: 2, label: "FADE", name: "Fade In/Out", cc: 104, nrpn: n(1, 44),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod1.wave", page: .mod1, slot: 4, label: "WAVE", name: "Waveform", cc: 106, nrpn: n(1, 46),
                    format: .options(Labels.lfoWaveforms)),
        DNParameter(id: "mod1.sph", page: .mod1, slot: 5, label: "SPH", name: "Start Phase / Slew", cc: 107, nrpn: n(1, 47)),
        DNParameter(id: "mod1.mode", page: .mod1, slot: 6, label: "MODE", name: "Trig Mode", cc: 108, nrpn: n(1, 48),
                    format: .options(Labels.lfoTrigModes)),
        DNParameter(id: "mod1.dep", page: .mod1, slot: 7, label: "DEP", name: "Depth", cc: 109, nrpn: n(1, 49),
                    format: .scaled(min: -64, max: 63, decimals: 2, unit: ""), defaultValue: 64, isHighResolution: true)
    ]

    /// LFO 2 (11.10, C.8) without DEST.
    static let mod2: [DNParameter] = [
        DNParameter(id: "mod2.spd", page: .mod2, slot: 0, label: "SPD", name: "Speed", cc: 111, nrpn: n(1, 50), format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod2.mult", page: .mod2, slot: 1, label: "MULT", name: "Multiplier", cc: 112, nrpn: n(1, 51),
                    format: .options(Labels.lfoMultiplier)),
        DNParameter(id: "mod2.fade", page: .mod2, slot: 2, label: "FADE", name: "Fade In/Out", cc: 113, nrpn: n(1, 52),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod2.wave", page: .mod2, slot: 4, label: "WAVE", name: "Waveform", cc: 115, nrpn: n(1, 54),
                    format: .options(Labels.lfoWaveforms)),
        DNParameter(id: "mod2.sph", page: .mod2, slot: 5, label: "SPH", name: "Start Phase / Slew", cc: 116, nrpn: n(1, 55)),
        DNParameter(id: "mod2.mode", page: .mod2, slot: 6, label: "MODE", name: "Trig Mode", cc: 117, nrpn: n(1, 56),
                    format: .options(Labels.lfoTrigModes)),
        DNParameter(id: "mod2.dep", page: .mod2, slot: 7, label: "DEP", name: "Depth", cc: 118, nrpn: n(1, 57),
                    format: .scaled(min: -64, max: 63, decimals: 2, unit: ""), defaultValue: 64, isHighResolution: true)
    ]

    /// LFO 3 (11.11, C.8): NRPN only. Audio tracks only.
    static let mod3: [DNParameter] = [
        DNParameter(id: "mod3.spd", page: .mod3, slot: 0, label: "SPD", name: "Speed", cc: nil, nrpn: n(1, 58), format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod3.mult", page: .mod3, slot: 1, label: "MULT", name: "Multiplier", cc: nil, nrpn: n(1, 59),
                    format: .options(Labels.lfoMultiplier)),
        DNParameter(id: "mod3.fade", page: .mod3, slot: 2, label: "FADE", name: "Fade In/Out", cc: nil, nrpn: n(1, 60),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "mod3.wave", page: .mod3, slot: 4, label: "WAVE", name: "Waveform", cc: nil, nrpn: n(1, 62),
                    format: .options(Labels.lfoWaveforms)),
        DNParameter(id: "mod3.sph", page: .mod3, slot: 5, label: "SPH", name: "Start Phase / Slew", cc: nil, nrpn: n(1, 70)),
        DNParameter(id: "mod3.mode", page: .mod3, slot: 6, label: "MODE", name: "Trig Mode", cc: nil, nrpn: n(1, 71),
                    format: .options(Labels.lfoTrigModes)),
        DNParameter(id: "mod3.dep", page: .mod3, slot: 7, label: "DEP", name: "Depth", cc: nil, nrpn: n(1, 72),
                    format: .scaled(min: -64, max: 63, decimals: 2, unit: ""), defaultValue: 64, isHighResolution: true)
    ]

    /// TRACK: app page for track controls without a device knob page — Mute, Track Level (C.1),
    /// Pattern Mute (C.12) and AMP HOLD, which the device shows on AMP knob B only in AHD mode.
    static let track: [DNParameter] = [
        DNParameter(id: "track.mute", page: .track, slot: 0, label: "MUTE", name: "Mute", cc: 94, nrpn: n(1, 108), format: .toggle),
        DNParameter(id: "track.level", page: .track, slot: 1, label: "LEV", name: "Track Level", cc: 95, nrpn: n(1, 110), defaultValue: 100),
        DNParameter(id: "track.patternMute", page: .track, slot: 2, label: "PMUT", name: "Pattern Mute", cc: 110, nrpn: n(1, 109), format: .toggle),
        DNParameter(id: "amp.hold", page: .track, slot: 3, label: "HOLD", name: "Amp Hold Time (AHD)", cc: 85, nrpn: n(1, 31),
                    format: .options(Labels.holdTime))
    ]

    /// MIDI tracks: Mute and Pattern Mute (no audio level, no AMP envelope).
    static var midiTrack: [DNParameter] { track.filter { ["track.mute", "track.patternMute"].contains($0.id) } }

    /// MIDI machine CC VAL1–8 on FLTR page 1 and VAL9–16 on AMP page 1 (A.2.5, C.11). The CC numbers they
    /// send are chosen with SEL1–16 on the second pages, which have no MIDI address.
    static let midiValues: [DNParameter] = [
        DNParameter(id: "midi.val1", page: .fltr1, slot: 0, label: "VAL1", name: "CC 1 Value", cc: 70, nrpn: n(1, 16)),
        DNParameter(id: "midi.val2", page: .fltr1, slot: 1, label: "VAL2", name: "CC 2 Value", cc: 71, nrpn: n(1, 17)),
        DNParameter(id: "midi.val3", page: .fltr1, slot: 2, label: "VAL3", name: "CC 3 Value", cc: 72, nrpn: n(1, 18)),
        DNParameter(id: "midi.val4", page: .fltr1, slot: 3, label: "VAL4", name: "CC 4 Value", cc: 73, nrpn: n(1, 19)),
        DNParameter(id: "midi.val5", page: .fltr1, slot: 4, label: "VAL5", name: "CC 5 Value", cc: 74, nrpn: n(1, 20)),
        DNParameter(id: "midi.val6", page: .fltr1, slot: 5, label: "VAL6", name: "CC 6 Value", cc: 75, nrpn: n(1, 21)),
        DNParameter(id: "midi.val7", page: .fltr1, slot: 6, label: "VAL7", name: "CC 7 Value", cc: 76, nrpn: n(1, 22)),
        DNParameter(id: "midi.val8", page: .fltr1, slot: 7, label: "VAL8", name: "CC 8 Value", cc: 77, nrpn: n(1, 23)),
        DNParameter(id: "midi.val9", page: .amp, slot: 0, label: "VAL9", name: "CC 9 Value", cc: 78, nrpn: n(1, 60)),
        DNParameter(id: "midi.val10", page: .amp, slot: 1, label: "VAL10", name: "CC 10 Value", cc: 79, nrpn: n(1, 61)),
        DNParameter(id: "midi.val11", page: .amp, slot: 2, label: "VAL11", name: "CC 11 Value", cc: 80, nrpn: n(1, 62)),
        DNParameter(id: "midi.val12", page: .amp, slot: 3, label: "VAL12", name: "CC 12 Value", cc: 81, nrpn: n(1, 63)),
        DNParameter(id: "midi.val13", page: .amp, slot: 4, label: "VAL13", name: "CC 13 Value", cc: 82, nrpn: n(1, 64)),
        DNParameter(id: "midi.val14", page: .amp, slot: 5, label: "VAL14", name: "CC 14 Value", cc: 83, nrpn: n(1, 65)),
        DNParameter(id: "midi.val15", page: .amp, slot: 6, label: "VAL15", name: "CC 15 Value", cc: 84, nrpn: n(1, 66)),
        DNParameter(id: "midi.val16", page: .amp, slot: 7, label: "VAL16", name: "CC 16 Value", cc: 85, nrpn: n(1, 67))
    ]

    /// Euclidean SEQUENCER menu ([FUNC]+[AMP], 10.6, C.6). LEN has no MIDI address.
    static let sequencer: [DNParameter] = [
        DNParameter(id: "euclid.pulses1", page: .sequencer, slot: 0, label: "PL1", name: "Pulse Generator 1", cc: nil, nrpn: n(3, 8)),
        DNParameter(id: "euclid.pulses2", page: .sequencer, slot: 1, label: "PL2", name: "Pulse Generator 2", cc: nil, nrpn: n(3, 9)),
        DNParameter(id: "euclid.mode", page: .sequencer, slot: 3, label: "EUC", name: "Euclidean Mode On/Off", cc: nil, nrpn: n(3, 14), format: .toggle),
        DNParameter(id: "euclid.rotation1", page: .sequencer, slot: 4, label: "RO1", name: "Rotation Generator 1", cc: nil, nrpn: n(3, 11)),
        DNParameter(id: "euclid.rotation2", page: .sequencer, slot: 5, label: "RO2", name: "Rotation Generator 2", cc: nil, nrpn: n(3, 12)),
        DNParameter(id: "euclid.trackRotation", page: .sequencer, slot: 6, label: "TRO", name: "Track Rotation", cc: nil, nrpn: n(3, 13)),
        DNParameter(id: "euclid.operator", page: .sequencer, slot: 7, label: "OP", name: "Boolean Operator", cc: nil, nrpn: n(3, 10), format: .options(["OR", "XOR", "AND", "SUB"]))
    ]
}
