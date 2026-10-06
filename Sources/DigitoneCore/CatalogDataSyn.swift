import Foundation

// SYN pages per machine (Appendix A.2). SYN page k knob X is addressed with "Data entry knob X
// (machine dependent)" of SYN PAGE k (Appendix C.3): CC 40/48/56/70 + knob, NRPN 1:73/81/89/97 + knob.
extension CatalogData {
    /// FM TONE (A.2.1, Appendix B): four pages. Empty knobs: SYN3 H, SYN4 E.
    static let fmTone: [DNParameter] = [
        DNParameter(id: "fmTone.syn1.algo", page: .syn1, slot: 0, label: "ALGO", name: "Algorithm", cc: 40, nrpn: n(1, 73),
                    format: .number(1...8, offset: 1)),
        DNParameter(id: "fmTone.syn1.ratioC", page: .syn1, slot: 1, label: "RAT C", name: "Ratio C", cc: 41, nrpn: n(1, 74)),
        DNParameter(id: "fmTone.syn1.ratioA", page: .syn1, slot: 2, label: "RAT A", name: "Ratio A", cc: 42, nrpn: n(1, 75)),
        DNParameter(id: "fmTone.syn1.ratioB", page: .syn1, slot: 3, label: "RAT B", name: "Ratio B (B1 · B2)", cc: 43, nrpn: n(1, 76)),
        DNParameter(id: "fmTone.syn1.harm", page: .syn1, slot: 4, label: "HARM", name: "Harmonics", cc: 44, nrpn: n(1, 77),
                    format: .scaled(min: -26, max: 25.59375, decimals: 2, unit: ""), defaultValue: 64, isHighResolution: true),
        DNParameter(id: "fmTone.syn1.detune", page: .syn1, slot: 5, label: "DTUN", name: "Detune", cc: 45, nrpn: n(1, 78)),
        DNParameter(id: "fmTone.syn1.feedback", page: .syn1, slot: 6, label: "FDBK", name: "Feedback", cc: 46, nrpn: n(1, 79)),
        DNParameter(id: "fmTone.syn1.mix", page: .syn1, slot: 7, label: "MIX", name: "Mix X/Y", cc: 47, nrpn: n(1, 80),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "fmTone.syn2.atkA", page: .syn2, slot: 0, label: "ATK A", name: "Attack Time A", cc: 48, nrpn: n(1, 81)),
        DNParameter(id: "fmTone.syn2.decA", page: .syn2, slot: 1, label: "DEC A", name: "Decay Time A", cc: 49, nrpn: n(1, 82)),
        DNParameter(id: "fmTone.syn2.endA", page: .syn2, slot: 2, label: "END A", name: "End Level A", cc: 50, nrpn: n(1, 83)),
        DNParameter(id: "fmTone.syn2.levA", page: .syn2, slot: 3, label: "LEV A", name: "Level A", cc: 51, nrpn: n(1, 84)),
        DNParameter(id: "fmTone.syn2.atkB", page: .syn2, slot: 4, label: "ATK B", name: "Attack Time B", cc: 52, nrpn: n(1, 85)),
        DNParameter(id: "fmTone.syn2.decB", page: .syn2, slot: 5, label: "DEC B", name: "Decay Time B", cc: 53, nrpn: n(1, 86)),
        DNParameter(id: "fmTone.syn2.endB", page: .syn2, slot: 6, label: "END B", name: "End Level B", cc: 54, nrpn: n(1, 87)),
        DNParameter(id: "fmTone.syn2.levB", page: .syn2, slot: 7, label: "LEV B", name: "Level B", cc: 55, nrpn: n(1, 88)),
        DNParameter(id: "fmTone.syn3.aDelay", page: .syn3, slot: 0, label: "ADEL", name: "Env. Delay A", cc: 56, nrpn: n(1, 89)),
        DNParameter(id: "fmTone.syn3.aTrig", page: .syn3, slot: 1, label: "ATRG", name: "Env. Trig A", cc: 57, nrpn: n(1, 90), format: .toggle),
        DNParameter(id: "fmTone.syn3.aReset", page: .syn3, slot: 2, label: "ARST", name: "Env. Reset A", cc: 58, nrpn: n(1, 91), format: .toggle),
        DNParameter(id: "fmTone.syn3.phaseReset", page: .syn3, slot: 3, label: "PHRT", name: "Phase Reset", cc: 59, nrpn: n(1, 92),
                    format: .options(["OFF", "ALL", "C", "A+B", "A+B2"])),
        DNParameter(id: "fmTone.syn3.bDelay", page: .syn3, slot: 4, label: "BDEL", name: "Env. Delay B", cc: 60, nrpn: n(1, 93)),
        DNParameter(id: "fmTone.syn3.bTrig", page: .syn3, slot: 5, label: "BTRG", name: "Env. Trig B", cc: 61, nrpn: n(1, 94), format: .toggle),
        DNParameter(id: "fmTone.syn3.bReset", page: .syn3, slot: 6, label: "BRST", name: "Env. Reset B", cc: 62, nrpn: n(1, 95), format: .toggle),
        DNParameter(id: "fmTone.syn4.offsetC", page: .syn4, slot: 0, label: "OFS C", name: "Ratio Offset C", cc: 70, nrpn: n(1, 97),
                    format: .bipolar, defaultValue: 64, isHighResolution: true),
        DNParameter(id: "fmTone.syn4.offsetA", page: .syn4, slot: 1, label: "OFS A", name: "Ratio Offset A", cc: 71, nrpn: n(1, 98),
                    format: .bipolar, defaultValue: 64, isHighResolution: true),
        DNParameter(id: "fmTone.syn4.offsetB1", page: .syn4, slot: 2, label: "OFS B1", name: "Ratio Offset B1", cc: 72, nrpn: n(1, 99),
                    format: .bipolar, defaultValue: 64, isHighResolution: true),
        DNParameter(id: "fmTone.syn4.offsetB2", page: .syn4, slot: 3, label: "OFS B2", name: "Ratio Offset B2", cc: 73, nrpn: n(1, 100),
                    format: .bipolar, defaultValue: 64, isHighResolution: true),
        DNParameter(id: "fmTone.syn4.keyTrackA", page: .syn4, slot: 5, label: "KEY A", name: "Key Track A", cc: 75, nrpn: n(1, 102)),
        DNParameter(id: "fmTone.syn4.keyTrackB1", page: .syn4, slot: 6, label: "KEY B1", name: "Key Track B1", cc: 76, nrpn: n(1, 103)),
        DNParameter(id: "fmTone.syn4.keyTrackB2", page: .syn4, slot: 7, label: "KEY B2", name: "Key Track B2", cc: 77, nrpn: n(1, 104))
    ]

    /// FM DRUM (A.2.2): four pages. Empty knobs: SYN3 E/F.
    static let fmDrum: [DNParameter] = [
        DNParameter(id: "fmDrum.syn1.tune", page: .syn1, slot: 0, label: "TUNE", name: "Tune", cc: 40, nrpn: n(1, 73),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "fmDrum.syn1.sweepTime", page: .syn1, slot: 1, label: "STIM", name: "Sweep Time", cc: 41, nrpn: n(1, 74)),
        DNParameter(id: "fmDrum.syn1.sweepDepth", page: .syn1, slot: 2, label: "SDEP", name: "Sweep Depth", cc: 42, nrpn: n(1, 75)),
        DNParameter(id: "fmDrum.syn1.algo", page: .syn1, slot: 3, label: "ALGO", name: "Algorithm", cc: 43, nrpn: n(1, 76),
                    format: .number(1...7, offset: 1)),
        DNParameter(id: "fmDrum.syn1.opC", page: .syn1, slot: 4, label: "OP.C", name: "Operator C Wave", cc: 44, nrpn: n(1, 77)),
        DNParameter(id: "fmDrum.syn1.opAB", page: .syn1, slot: 5, label: "OP.AB", name: "Operator A·B Wave", cc: 45, nrpn: n(1, 78)),
        DNParameter(id: "fmDrum.syn1.feedback", page: .syn1, slot: 6, label: "FDBK", name: "Feedback", cc: 46, nrpn: n(1, 79)),
        DNParameter(id: "fmDrum.syn1.fold", page: .syn1, slot: 7, label: "FOLD", name: "Fold", cc: 47, nrpn: n(1, 80)),
        DNParameter(id: "fmDrum.syn2.ratioA", page: .syn2, slot: 0, label: "RAT A", name: "Ratio A", cc: 48, nrpn: n(1, 81), isHighResolution: true),
        DNParameter(id: "fmDrum.syn2.decA", page: .syn2, slot: 1, label: "DEC A", name: "Decay A", cc: 49, nrpn: n(1, 82)),
        DNParameter(id: "fmDrum.syn2.endA", page: .syn2, slot: 2, label: "END A", name: "End A", cc: 50, nrpn: n(1, 83)),
        DNParameter(id: "fmDrum.syn2.modA", page: .syn2, slot: 3, label: "MOD A", name: "Mod A", cc: 51, nrpn: n(1, 84)),
        DNParameter(id: "fmDrum.syn2.ratioB", page: .syn2, slot: 4, label: "RAT B", name: "Ratio B", cc: 52, nrpn: n(1, 85), isHighResolution: true),
        DNParameter(id: "fmDrum.syn2.decB", page: .syn2, slot: 5, label: "DEC B", name: "Decay B", cc: 53, nrpn: n(1, 86)),
        DNParameter(id: "fmDrum.syn2.endB", page: .syn2, slot: 6, label: "END B", name: "End B", cc: 54, nrpn: n(1, 87)),
        DNParameter(id: "fmDrum.syn2.modB", page: .syn2, slot: 7, label: "MOD B", name: "Mod B", cc: 55, nrpn: n(1, 88)),
        DNParameter(id: "fmDrum.syn3.hold", page: .syn3, slot: 0, label: "HOLD", name: "Body Hold", cc: 56, nrpn: n(1, 89)),
        DNParameter(id: "fmDrum.syn3.decay", page: .syn3, slot: 1, label: "DEC", name: "Body Decay", cc: 57, nrpn: n(1, 90),
                    format: .options(Labels.decayTime)),
        DNParameter(id: "fmDrum.syn3.phaseC", page: .syn3, slot: 2, label: "PH.C", name: "OP C Phase", cc: 58, nrpn: n(1, 91),
                    format: .options(Labels.phaseC)),
        DNParameter(id: "fmDrum.syn3.level", page: .syn3, slot: 3, label: "LEV", name: "Body Level", cc: 59, nrpn: n(1, 92)),
        DNParameter(id: "fmDrum.syn3.noiseReset", page: .syn3, slot: 6, label: "NRST", name: "Noise Reset", cc: 62, nrpn: n(1, 95), format: .toggle),
        DNParameter(id: "fmDrum.syn3.noiseRingMod", page: .syn3, slot: 7, label: "NRM", name: "Noise Ring Mod", cc: 63, nrpn: n(1, 96),
                    format: .toggle),
        DNParameter(id: "fmDrum.syn4.noiseHold", page: .syn4, slot: 0, label: "NHLD", name: "Noise Hold", cc: 70, nrpn: n(1, 97)),
        DNParameter(id: "fmDrum.syn4.noiseDecay", page: .syn4, slot: 1, label: "NDEC", name: "Noise Decay", cc: 71, nrpn: n(1, 98),
                    format: .options(Labels.decayTime)),
        DNParameter(id: "fmDrum.syn4.transient", page: .syn4, slot: 2, label: "TRAN", name: "Drum Transient", cc: 72, nrpn: n(1, 99)),
        DNParameter(id: "fmDrum.syn4.transientLevel", page: .syn4, slot: 3, label: "TLEV", name: "Transient Level", cc: 73, nrpn: n(1, 100)),
        DNParameter(id: "fmDrum.syn4.noiseBase", page: .syn4, slot: 4, label: "BASE", name: "Noise Base", cc: 74, nrpn: n(1, 101)),
        DNParameter(id: "fmDrum.syn4.noiseWidth", page: .syn4, slot: 5, label: "WDTH", name: "Noise Width", cc: 75, nrpn: n(1, 102),
                    defaultValue: 127),
        DNParameter(id: "fmDrum.syn4.noiseGrain", page: .syn4, slot: 6, label: "GRAN", name: "Noise Grain", cc: 76, nrpn: n(1, 103)),
        DNParameter(id: "fmDrum.syn4.noiseLevel", page: .syn4, slot: 7, label: "NLEV", name: "Noise Level", cc: 77, nrpn: n(1, 104))
    ]

    /// WAVETONE (A.2.3): three pages. Empty knob: SYN2 G.
    static let wavetone: [DNParameter] = [
        DNParameter(id: "wavetone.syn1.tune1", page: .syn1, slot: 0, label: "TUN1", name: "Osc1 Tune", cc: 40, nrpn: n(1, 73),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "wavetone.syn1.wave1", page: .syn1, slot: 1, label: "WAV1", name: "Osc1 Waveform", cc: 41, nrpn: n(1, 74)),
        DNParameter(id: "wavetone.syn1.pd1", page: .syn1, slot: 2, label: "PD1", name: "Osc1 Phase Distortion", cc: 42, nrpn: n(1, 75)),
        DNParameter(id: "wavetone.syn1.level1", page: .syn1, slot: 3, label: "LEV1", name: "Osc1 Level", cc: 43, nrpn: n(1, 76)),
        DNParameter(id: "wavetone.syn1.tune2", page: .syn1, slot: 4, label: "TUN2", name: "Osc2 Tune", cc: 44, nrpn: n(1, 77),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "wavetone.syn1.wave2", page: .syn1, slot: 5, label: "WAV2", name: "Osc2 Waveform", cc: 45, nrpn: n(1, 78)),
        DNParameter(id: "wavetone.syn1.pd2", page: .syn1, slot: 6, label: "PD2", name: "Osc2 Phase Distortion", cc: 46, nrpn: n(1, 79)),
        DNParameter(id: "wavetone.syn1.level2", page: .syn1, slot: 7, label: "LEV2", name: "Osc2 Level", cc: 47, nrpn: n(1, 80)),
        DNParameter(id: "wavetone.syn2.offset1", page: .syn2, slot: 0, label: "OFS1", name: "Osc1 Lin Offset", cc: 48, nrpn: n(1, 81),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "wavetone.syn2.table1", page: .syn2, slot: 1, label: "TBL1", name: "Osc1 Wavetable", cc: 49, nrpn: n(1, 82),
                    format: .options(["PRIM", "HARM"])),
        DNParameter(id: "wavetone.syn2.oscMod", page: .syn2, slot: 2, label: "MOD", name: "Oscillator Modulation", cc: 50, nrpn: n(1, 83),
                    format: .options(["OFF", "RING MOD", "RING MOD FIXED", "HARD SYNC"])),
        DNParameter(id: "wavetone.syn2.phaseReset", page: .syn2, slot: 3, label: "RSET", name: "Oscillator Phase Reset", cc: 51, nrpn: n(1, 84),
                    format: .options(["OFF", "ON", "RAND"])),
        DNParameter(id: "wavetone.syn2.offset2", page: .syn2, slot: 4, label: "OFS2", name: "Osc2 Lin Offset", cc: 52, nrpn: n(1, 85),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "wavetone.syn2.table2", page: .syn2, slot: 5, label: "TBL2", name: "Osc2 Wavetable", cc: 53, nrpn: n(1, 86),
                    format: .options(["PRIM", "HARM"])),
        DNParameter(id: "wavetone.syn2.drift", page: .syn2, slot: 7, label: "DRIF", name: "Oscillator Drift", cc: 55, nrpn: n(1, 88)),
        DNParameter(id: "wavetone.syn3.noiseAttack", page: .syn3, slot: 0, label: "ATK", name: "Noise Attack", cc: 56, nrpn: n(1, 89)),
        DNParameter(id: "wavetone.syn3.noiseHold", page: .syn3, slot: 1, label: "HOLD", name: "Noise Hold", cc: 57, nrpn: n(1, 90),
                    format: .options(Labels.holdTime)),
        DNParameter(id: "wavetone.syn3.noiseDecay", page: .syn3, slot: 2, label: "DEC", name: "Noise Decay", cc: 58, nrpn: n(1, 91)),
        DNParameter(id: "wavetone.syn3.noiseLevel", page: .syn3, slot: 3, label: "NLEV", name: "Noise Level", cc: 59, nrpn: n(1, 92)),
        DNParameter(id: "wavetone.syn3.noiseBase", page: .syn3, slot: 4, label: "BASE", name: "Noise Base", cc: 60, nrpn: n(1, 93)),
        DNParameter(id: "wavetone.syn3.noiseWidth", page: .syn3, slot: 5, label: "WDTH", name: "Noise Width", cc: 61, nrpn: n(1, 94),
                    defaultValue: 127),
        DNParameter(id: "wavetone.syn3.noiseType", page: .syn3, slot: 6, label: "TYPE", name: "Noise Type", cc: 62, nrpn: n(1, 95),
                    format: .options(["GRAIN", "TUNED", "S&H"])),
        DNParameter(id: "wavetone.syn3.noiseChar", page: .syn3, slot: 7, label: "CHAR", name: "Noise Character", cc: 63, nrpn: n(1, 96))
    ]

    /// SWARMER (A.2.4): one page.
    static let swarmer: [DNParameter] = [
        DNParameter(id: "swarmer.syn1.tune", page: .syn1, slot: 0, label: "TUNE", name: "Tune", cc: 40, nrpn: n(1, 73),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "swarmer.syn1.swarmWave", page: .syn1, slot: 1, label: "SWRM", name: "Swarm Waveform", cc: 41, nrpn: n(1, 74)),
        DNParameter(id: "swarmer.syn1.detune", page: .syn1, slot: 2, label: "DET", name: "Detune", cc: 42, nrpn: n(1, 75)),
        DNParameter(id: "swarmer.syn1.mix", page: .syn1, slot: 3, label: "MIX", name: "Mix", cc: 43, nrpn: n(1, 76)),
        DNParameter(id: "swarmer.syn1.mainOctave", page: .syn1, slot: 4, label: "M.OCT", name: "Main Octave", cc: 44, nrpn: n(1, 77),
                    format: .options(["0", "-1", "-2"])),
        DNParameter(id: "swarmer.syn1.mainWave", page: .syn1, slot: 5, label: "MAIN", name: "Main Waveform", cc: 45, nrpn: n(1, 78)),
        DNParameter(id: "swarmer.syn1.animation", page: .syn1, slot: 6, label: "ANIM", name: "Swarm Animation", cc: 46, nrpn: n(1, 79)),
        DNParameter(id: "swarmer.syn1.noiseMod", page: .syn1, slot: 7, label: "N.MOD", name: "Noise Modulation", cc: 47, nrpn: n(1, 80))
    ]

    /// MIDI machine SYN page (A.2.5): one page; every value defaults to OFF on the device.
    static let midi: [DNParameter] = [
        DNParameter(id: "midi.syn1.channel", page: .syn1, slot: 0, label: "CHAN", name: "MIDI Channel", cc: 40, nrpn: n(1, 73),
                    format: .options(Labels.midiChannels)),
        DNParameter(id: "midi.syn1.bank", page: .syn1, slot: 1, label: "BANK", name: "Bank (CC 0)", cc: 41, nrpn: n(1, 74)),
        DNParameter(id: "midi.syn1.subBank", page: .syn1, slot: 2, label: "SBNK", name: "Sub Bank (CC 32)", cc: 42, nrpn: n(1, 75)),
        DNParameter(id: "midi.syn1.program", page: .syn1, slot: 3, label: "PROG", name: "Program Change", cc: 43, nrpn: n(1, 76)),
        DNParameter(id: "midi.syn1.pitchBend", page: .syn1, slot: 4, label: "PB", name: "Pitch Bend", cc: 44, nrpn: n(1, 77),
                    format: .bipolar, defaultValue: 64),
        DNParameter(id: "midi.syn1.aftertouch", page: .syn1, slot: 5, label: "AT", name: "Aftertouch", cc: 45, nrpn: n(1, 78)),
        DNParameter(id: "midi.syn1.modWheel", page: .syn1, slot: 6, label: "MW", name: "Mod Wheel", cc: 46, nrpn: n(1, 79)),
        DNParameter(id: "midi.syn1.breath", page: .syn1, slot: 7, label: "BC", name: "Breath Controller", cc: 47, nrpn: n(1, 80))
    ]
}
