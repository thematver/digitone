import Foundation

// Global pages, addressed on FX CONTROL CH (13.4.3, Appendix C.9–C.10, C.12). Each device page
// also has a LEVEL/DATA volume beside the eight knobs; the catalog files it on a free knob.
extension CatalogData {
    /// DELAY, SEND FX page 1 (12.2). Knob G is empty on the device and holds the mix volume.
    static let delay: [DNParameter] = [
        DNParameter(id: "delay.time", page: .delay, slot: 0, label: "TIME", name: "Delay Time", cc: 21, nrpn: n(2, 0),
                    format: .number(1...128, offset: 1), defaultValue: 31, isHighResolution: true),
        DNParameter(id: "delay.pingPong", page: .delay, slot: 1, label: "X", name: "Ping-pong", cc: 22, nrpn: n(2, 1), format: .toggle),
        DNParameter(id: "delay.width", page: .delay, slot: 2, label: "WID", name: "Stereo Width", cc: 23, nrpn: n(2, 2),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "delay.feedback", page: .delay, slot: 3, label: "FDBK", name: "Feedback", cc: 24, nrpn: n(2, 3)),
        DNParameter(id: "delay.hpf", page: .delay, slot: 4, label: "HPF", name: "Highpass Filter", cc: 25, nrpn: n(2, 4)),
        DNParameter(id: "delay.lpf", page: .delay, slot: 5, label: "LPF", name: "Lowpass Filter", cc: 26, nrpn: n(2, 5), defaultValue: 127),
        DNParameter(id: "delay.volume", page: .delay, slot: 6, label: "VOL", name: "Mix Volume", cc: 28, nrpn: n(2, 7), defaultValue: 100),
        DNParameter(id: "delay.reverb", page: .delay, slot: 7, label: "REV", name: "Reverb Send", cc: 27, nrpn: n(2, 6))
    ]

    /// REVERB, SEND FX page 2 (12.3). Knobs G/H are empty; G holds the mix volume.
    static let reverb: [DNParameter] = [
        DNParameter(id: "reverb.preDelay", page: .reverb, slot: 0, label: "PRE", name: "Predelay", cc: 29, nrpn: n(2, 8)),
        DNParameter(id: "reverb.decay", page: .reverb, slot: 1, label: "DEC", name: "Decay Time", cc: 30, nrpn: n(2, 9)),
        DNParameter(id: "reverb.freq", page: .reverb, slot: 2, label: "FREQ", name: "Shelving Freq", cc: 31, nrpn: n(2, 10)),
        DNParameter(id: "reverb.gain", page: .reverb, slot: 3, label: "GAIN", name: "Shelving Gain", cc: 89, nrpn: n(2, 11), defaultValue: 127),
        DNParameter(id: "reverb.hpf", page: .reverb, slot: 4, label: "HPF", name: "Highpass Filter", cc: 90, nrpn: n(2, 12)),
        DNParameter(id: "reverb.lpf", page: .reverb, slot: 5, label: "LPF", name: "Lowpass Filter", cc: 91, nrpn: n(2, 13), defaultValue: 127),
        DNParameter(id: "reverb.volume", page: .reverb, slot: 6, label: "VOL", name: "Mix Volume", cc: 92, nrpn: n(2, 15), defaultValue: 100)
    ]

    /// CHORUS, SEND FX page 3 (12.4). Knobs E/F are empty; E holds the mix volume.
    static let chorus: [DNParameter] = [
        DNParameter(id: "chorus.depth", page: .chorus, slot: 0, label: "DPTH", name: "Depth", cc: 16, nrpn: n(2, 41)),
        DNParameter(id: "chorus.speed", page: .chorus, slot: 1, label: "SPD", name: "Speed", cc: 9, nrpn: n(2, 42)),
        DNParameter(id: "chorus.hpf", page: .chorus, slot: 2, label: "HPF", name: "High Pass Filter", cc: 70, nrpn: n(2, 43)),
        DNParameter(id: "chorus.width", page: .chorus, slot: 3, label: "WDTH", name: "Width", cc: 71, nrpn: n(2, 44), defaultValue: 127),
        DNParameter(id: "chorus.volume", page: .chorus, slot: 4, label: "VOL", name: "Mix Volume", cc: 14, nrpn: n(2, 47), defaultValue: 100),
        DNParameter(id: "chorus.delay", page: .chorus, slot: 6, label: "DEL", name: "Delay Send", cc: 12, nrpn: n(2, 45)),
        DNParameter(id: "chorus.reverb", page: .chorus, slot: 7, label: "REV", name: "Reverb Send", cc: 13, nrpn: n(2, 46))
    ]

    /// COMPRESSOR, MIXER page 1 (12.5). Its LEVEL/DATA (Pattern Volume) is on MIXER.
    static let compressor: [DNParameter] = [
        DNParameter(id: "comp.threshold", page: .compressor, slot: 0, label: "THR", name: "Threshold", cc: 111, nrpn: n(2, 16), defaultValue: 127),
        DNParameter(id: "comp.attack", page: .compressor, slot: 1, label: "ATK", name: "Attack Time", cc: 112, nrpn: n(2, 17)),
        DNParameter(id: "comp.release", page: .compressor, slot: 2, label: "REL", name: "Release Time", cc: 113, nrpn: n(2, 18)),
        DNParameter(id: "comp.makeup", page: .compressor, slot: 3, label: "MUP", name: "Makeup Gain", cc: 114, nrpn: n(2, 19)),
        DNParameter(id: "comp.ratio", page: .compressor, slot: 4, label: "RAT", name: "Ratio", cc: 115, nrpn: n(2, 20),
                    format: .options(Labels.compressorRatios)),
        DNParameter(id: "comp.sidechainSource", page: .compressor, slot: 5, label: "SCS", name: "Sidechain Source", cc: 116, nrpn: n(2, 21),
                    format: .options(Labels.sidechainSources)),
        DNParameter(id: "comp.sidechainFilter", page: .compressor, slot: 6, label: "SCF", name: "Sidechain Filter", cc: 117, nrpn: n(2, 22),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "comp.mix", page: .compressor, slot: 7, label: "MIX", name: "Dry/Wet Mix", cc: 118, nrpn: n(2, 23))
    ]

    /// MIXER: EXTERNAL MIXER page 5 (12.9) knobs A–C and E–G, master overdrive (FX MIXER, 12.8) on the
    /// empty knob D and Pattern Volume (LEVEL/DATA of every mixer page) on the empty knob H. With DUAL ON
    /// the same addresses control input L; input R (page 6) is exposed on INPUT R. INTERNAL MIXER pages are
    /// the TRACK LEV of each track; FX MIXER DEL/REV/CHR are the mix volumes on DELAY/REVERB/CHORUS.
    static let mixer: [DNParameter] = [
        DNParameter(id: "mixer.inputLevel", page: .mixer, slot: 0, label: "IN", name: "Input Level", cc: 72, nrpn: n(2, 30)),
        DNParameter(id: "mixer.dualMono", page: .mixer, slot: 1, label: "DUAL", name: "Dual Mono", cc: 82, nrpn: n(2, 40), format: .toggle),
        DNParameter(id: "mixer.inputBalance", page: .mixer, slot: 2, label: "BAL", name: "Input Balance", cc: 74, nrpn: n(2, 32),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "mixer.masterOverdrive", page: .mixer, slot: 3, label: "MOVD", name: "Master Overdrive", cc: 17, nrpn: n(2, 50)),
        DNParameter(id: "mixer.inputDelay", page: .mixer, slot: 4, label: "DEL", name: "Input Delay Send", cc: 78, nrpn: n(2, 36)),
        DNParameter(id: "mixer.inputReverb", page: .mixer, slot: 5, label: "REV", name: "Input Reverb Send", cc: 80, nrpn: n(2, 38)),
        DNParameter(id: "mixer.inputChorus", page: .mixer, slot: 6, label: "CHR", name: "Input Chorus Send", cc: 76, nrpn: n(2, 34)),
        DNParameter(id: "mixer.patternVolume", page: .mixer, slot: 7, label: "VOL", name: "Pattern Volume", cc: 119, nrpn: n(2, 24),
                    defaultValue: 100)
    ]

    /// External right input controls, active with DUAL ON (12.9, C.10).
    static let mixerRight: [DNParameter] = [
        DNParameter(id: "mixer.inputRLevel", page: .mixerRight, slot: 0, label: "IN R", name: "Input R Level", cc: 73, nrpn: n(2, 31)),
        DNParameter(id: "mixer.inputRPan", page: .mixerRight, slot: 2, label: "PAN", name: "Input R Pan", cc: 75, nrpn: n(2, 33), format: .bipolar, defaultValue: 64),
        DNParameter(id: "mixer.inputRDelay", page: .mixerRight, slot: 4, label: "DEL", name: "Input R Delay Send", cc: 79, nrpn: n(2, 37)),
        DNParameter(id: "mixer.inputRReverb", page: .mixerRight, slot: 5, label: "REV", name: "Input R Reverb Send", cc: 81, nrpn: n(2, 39)),
        DNParameter(id: "mixer.inputRChorus", page: .mixerRight, slot: 6, label: "CHR", name: "Input R Chorus Send", cc: 77, nrpn: n(2, 35))
    ]
}
