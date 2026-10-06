import Foundation

extension CatalogData {
    /// Option labels for `DNValueFormat.options`, as printed in the manual.
    enum Labels {
        /// MIDI notes 0–127 in Elektron naming: C0…G10, C5 = 60 (8.4).
        static let notes: [String] = (0...127).map { names[$0 % 12] + String($0 / 12) }
        /// 0–126 fixed, then NOTE (AMP HOLD, WAVETONE noise HOLD).
        static let holdTime: [String] = (0...126).map(String.init) + ["NOTE"]
        /// 0–126, last value infinite (FM DRUM DEC/NDEC).
        static let decayTime: [String] = (0...126).map(String.init) + ["INF"]
        /// FM DRUM PH.C: phase in degrees 0–90, 91 = OFF.
        static let phaseC: [String] = (0...90).map(String.init) + ["OFF"]
        /// LFO MULT: tempo-synced, then fixed 120 BPM (11.9).
        static let lfoMultiplier: [String] = multiplierSteps.map { "BPM \($0)" } + multiplierSteps
        static let lfoWaveforms = ["TRI", "SINE", "SQR", "SAW", "EXPO", "RAMP", "RAND"]
        static let lfoTrigModes = ["FREE", "TRIG", "HOLD", "ONE", "HALF"]
        static let prePost = ["PRE", "POST"]
        static let compressorRatios = ["1.50", "2.00", "3.00", "4.00", "6.00", "8.00", "16.00", "20.00"]
        static let sidechainSources: [String] = ["COMP MIX", "NOT COMP"] + (1...16).map { "TRK\($0)" } + ["IN LR", "IN L", "IN R"]
        static let midiChannels: [String] = ["OFF"] + (1...16).map(String.init)

        /// LFO DEST list (Appendix D) as the device scrolls it for LFO `lfo` on `machine`: an LFO lists only
        /// earlier LFOs, SYN entries carry the machine's knob labels page by page (A–H, empty knobs skipped).
        static func lfoDestinations(_ machine: DNMachine, lfo: Int, syn: [DNParameter]) -> [String] {
            var labels = ["NONE"]
            for source in 1..<lfo { labels += lfoTargets.map { "LFO\(source) \($0)" } }
            if machine == .midi {
                return labels + midiSynTargets.map { "SYN \($0)" } + (1...16).map { "CC VAL\($0)" }
            }
            return labels + syn.map { "SYN \($0.label)" } + filterTargets.map { "FLTR \($0)" }
                + ampTargets.map { "AMP \($0)" } + fxTargets.map { "FX \($0)" }
        }

        private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        private static let multiplierSteps = ["1", "2", "4", "8", "16", "32", "64", "128", "256", "512", "1K", "2K"]
        private static let lfoTargets = ["SPD", "MULT", "FADE", "WAVE", "SPH", "MODE", "DEP"]
        private static let filterTargets = ["ATK", "DEC", "SUS", "REL", "FREQ", "F", "G", "ENV", "DEL", "KEY.T", "BASE", "WDTH", "RSET"]
        private static let ampTargets = ["ATK", "HOLD", "DEC", "SUS", "REL", "PAN", "VOL"]
        private static let fxTargets = ["DEL", "REV", "CHR", "BR", "SRR", "SR.RT", "OVER"]
        private static let midiSynTargets = ["PB", "AT", "MW", "BC"]
    }
}
