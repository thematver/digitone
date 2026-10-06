import XCTest
@testable import DigitoneCore

final class HardwareCatalogTests: XCTestCase {
    // MARK: Fixture: docs/research/dn2-parameters.json

    private struct Doc: Decodable {
        var pages: [String: [String]]
        var parameters: [Parameter]
        var appendixC: [Row]
        var unmapped: [Unmapped]
        var filterMachines: [FilterMachine]
        var lfoDestinations: [String: [String]]
        var factoryChannels: FactoryChannels
    }

    private struct Parameter: Decodable {
        var id, scope, page, knob, label, name, source, notes: String
        var machines: [String]
        var slot, `default`: Int
        var cc, nrpn: Int?
        var format: Format
        var defaultStated, highResolution: Bool
    }

    private struct Row: Decodable {
        var section, table, parameter, scope: String
        var cc, nrpn: Int?
        var catalogIds: [String]
        var unmapped: String?
        var catalogOmitsCC: Bool
    }

    private struct Unmapped: Decodable {
        var key, reason: String
        var cc, nrpn: Int?
    }

    private struct FilterMachine: Decodable {
        var machine: String
        var F: String
        var G: String?
    }

    private struct FactoryChannels: Decodable {
        var trackChannels: [Int]
        var fxControlChannel: Int?
        var autoChannel: Int
        var programChangeInChannel: String
    }

    private struct Format: Decodable, Equatable {
        var kind: String
        var min, max: Double?
        var offset, decimals: Int?
        var labels: [String]?
        var unit: String?
    }

    private static let doc: Doc? = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/research/dn2-parameters.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Doc.self, from: data)
    }()

    private func loadDoc(file: StaticString = #filePath, line: UInt = #line) throws -> Doc {
        try XCTUnwrap(Self.doc, "docs/research/dn2-parameters.json is missing or does not decode", file: file, line: line)
    }

    private func format(_ format: DNValueFormat) -> Format {
        switch format {
        case .number(let range, let offset):
            Format(kind: "number", min: Double(range.lowerBound), max: Double(range.upperBound), offset: offset)
        case .bipolar: Format(kind: "bipolar")
        case .toggle: Format(kind: "toggle")
        case .options(let labels): Format(kind: "options", labels: labels)
        case .scaled(let min, let max, let decimals, let unit):
            Format(kind: "scaled", min: min, max: max, decimals: decimals, unit: unit)
        }
    }

    private var everyParameter: [DNParameter] {
        DNMachine.allCases.flatMap { HardwareCatalog.parameters(for: $0) }
            + HardwareCatalog.globalPages.flatMap { HardwareCatalog.parameters(on: $0, machine: .fmTone) }
    }

    private func param(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> DNParameter {
        try XCTUnwrap(HardwareCatalog.parameter(id: id), "missing \(id)", file: file, line: line)
    }

    // MARK: Structure

    func testIdsAreUniqueAcrossTheCatalog() {
        let groups = Dictionary(grouping: everyParameter, by: \.id)
        XCTAssertGreaterThan(groups.count, 200)
        for (id, members) in groups {
            // The same id may appear for several machines, but only as the very same parameter.
            XCTAssertEqual(Set(members).count, 1, "\(id) differs between machines")
        }
    }

    func testEveryPageFitsTheEightKnobs() {
        func check(_ page: DNPage, _ list: [DNParameter], _ context: String) {
            XCTAssertFalse(list.isEmpty, "\(context) \(page.title) is offered but empty")
            XCTAssertLessThanOrEqual(list.count, 8, "\(context) \(page.title)")
            XCTAssertEqual(Set(list.map(\.slot)).count, list.count, "\(context) \(page.title) reuses a knob")
            XCTAssertTrue(list.allSatisfy { (0...7).contains($0.slot) && $0.page == page }, "\(context) \(page.title)")
            XCTAssertEqual(list.map(\.slot), list.map(\.slot).sorted(), "\(context) \(page.title) is not in A…H order")
        }
        for machine in DNMachine.allCases {
            for page in HardwareCatalog.pages(for: machine) {
                check(page, HardwareCatalog.parameters(on: page, machine: machine), machine.title)
            }
        }
        for page in HardwareCatalog.globalPages {
            check(page, HardwareCatalog.parameters(on: page, machine: .midi), "global")
            XCTAssertEqual(HardwareCatalog.parameters(on: page, machine: .midi), HardwareCatalog.parameters(on: page, machine: .fmTone))
        }
    }

    func testPagesExistOnlyWhereTheMachineHasThem() throws {
        let synPages: [DNMachine: [DNPage]] = [.fmTone: [.syn1, .syn2, .syn3, .syn4], .fmDrum: [.syn1, .syn2, .syn3, .syn4],
                                              .wavetone: [.syn1, .syn2, .syn3], .swarmer: [.syn1], .midi: [.syn1]]
        for machine in DNMachine.allCases {
            let pages = HardwareCatalog.pages(for: machine)
            XCTAssertEqual(pages.filter { $0.rawValue.hasPrefix("syn") }, synPages[machine], machine.title)
            XCTAssertFalse(pages.contains { $0.isGlobal }, machine.title)
            XCTAssertEqual(pages, DNPage.allCases.filter { pages.contains($0) }, "\(machine.title) pages out of device order")
        }
        let audio: [DNPage] = [.trig, .fltr1, .fltr2, .amp, .fx, .mod1, .mod2, .mod3, .sequencer, .track]
        XCTAssertEqual(HardwareCatalog.pages(for: .swarmer), [DNPage.trig, .syn1] + Array(audio.dropFirst()))
        // MIDI tracks: no FX page, two LFOs, FLTR2/AMP2 (SEL1–16) have no MIDI address.
        XCTAssertEqual(HardwareCatalog.pages(for: .midi), [.trig, .syn1, .fltr1, .amp, .mod1, .mod2, .sequencer, .track])
        let doc = try loadDoc()
        for machine in DNMachine.allCases {
            XCTAssertEqual(doc.pages[machine.rawValue], HardwareCatalog.pages(for: machine).map(\.rawValue))
        }
        XCTAssertEqual(doc.pages["global"], HardwareCatalog.globalPages.map(\.rawValue))
    }

    func testTrackAndGlobalPagesUseTheirOwnNRPNBanks() {
        for machine in DNMachine.allCases {
            for parameter in HardwareCatalog.parameters(for: machine) {
                XCTAssertNotNil(parameter.cc ?? parameter.nrpn, parameter.id)
                if let nrpn = parameter.nrpn { XCTAssertTrue([1, 3].contains(nrpn / 128), parameter.id) }
            }
        }
        for page in HardwareCatalog.globalPages {
            for parameter in HardwareCatalog.parameters(on: page, machine: .fmTone) {
                XCTAssertEqual(parameter.nrpn.map { $0 / 128 }, 2, parameter.id)
            }
        }
    }

    func testAddressesAreUniqueWithinEachChannelScope() {
        func assertUnique(_ list: [DNParameter], _ scope: String) {
            for (key, values) in [("CC", list.compactMap(\.cc)), ("NRPN", list.compactMap(\.nrpn))] {
                let duplicates = Dictionary(grouping: values, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
                XCTAssertEqual(duplicates, [], "\(scope): duplicate \(key)")
            }
        }
        for machine in DNMachine.allCases { assertUnique(HardwareCatalog.parameters(for: machine), machine.title) }
        assertUnique(HardwareCatalog.globalPages.flatMap { HardwareCatalog.parameters(on: $0, machine: .fmTone) }, "global")
    }

    func testTheManualsDuplicateCCIsAddressedByNRPNOnly() throws {
        // C.5 prints CC 86 for both Decay Time and Sustain Level; the published NRPNs differ.
        let decay = try param("amp.dec"), sustain = try param("amp.sus")
        XCTAssertEqual(decay.cc, 86)
        XCTAssertNil(sustain.cc)
        XCTAssertEqual(sustain.nrpn, 128 + 33)
        let flagged = try loadDoc().appendixC.filter(\.catalogOmitsCC)
        XCTAssertEqual(flagged.map(\.parameter), ["Sustain Level"])
        XCTAssertEqual(flagged.first?.cc, 86)
    }

    // MARK: Appendix C coverage

    func testEveryAppendixCRowIsReachable() throws {
        let doc = try loadDoc()
        XCTAssertEqual(doc.appendixC.count, 167, "C.1–C.12 rows")
        XCTAssertTrue(doc.unmapped.isEmpty, "All published Appendix C addresses must be exposed")
        let unmapped = Dictionary(uniqueKeysWithValues: doc.unmapped.map { ($0.key, $0) })
        for row in doc.appendixC {
            let context = "\(row.section) / \(row.table) / \(row.parameter)"
            XCTAssertNotNil(row.cc ?? row.nrpn, context)
            if let key = row.unmapped {
                XCTAssertTrue(row.catalogIds.isEmpty, context)
                let entry = try XCTUnwrap(unmapped[key], context)
                XCTAssertFalse(entry.reason.isEmpty, context)
                XCTAssertEqual(entry.nrpn, row.nrpn, context)
                XCTAssertEqual(entry.cc, row.cc, context)
                XCTAssertNil(everyParameter.first { $0.nrpn == row.nrpn && ($0.page.isGlobal == (row.scope == "global")) },
                             "\(context) is listed as unmapped but reachable")
                continue
            }
            XCTAssertFalse(row.catalogIds.isEmpty, "\(context) is neither mapped nor listed as unmapped")
            for id in row.catalogIds {
                let parameter = try param(id)
                XCTAssertEqual(parameter.nrpn, row.nrpn, "\(context) → \(id)")
                XCTAssertEqual(parameter.cc, row.catalogOmitsCC ? nil : row.cc, "\(context) → \(id)")
                XCTAssertEqual(parameter.page.isGlobal, row.scope == "global", "\(context) → \(id)")
            }
        }
        // Every catalog parameter traces back to at least one Appendix C row.
        let referenced = Set(doc.appendixC.flatMap(\.catalogIds))
        XCTAssertEqual(Set(everyParameter.map(\.id)).subtracting(referenced), [])
    }

    func testSynKnobsUseTheDataEntryAddressOfTheirPage() {
        let base: [DNPage: (cc: Int, nrpn: Int)] = [.syn1: (40, 128 + 73), .syn2: (48, 128 + 81),
                                                    .syn3: (56, 128 + 89), .syn4: (70, 128 + 97)]
        for machine in DNMachine.allCases {
            for page in HardwareCatalog.pages(for: machine) {
                guard let address = base[page] else { continue }
                for parameter in HardwareCatalog.parameters(on: page, machine: machine) {
                    XCTAssertEqual(parameter.cc, address.cc + parameter.slot, parameter.id)
                    XCTAssertEqual(parameter.nrpn, address.nrpn + parameter.slot, parameter.id)
                    XCTAssertTrue(parameter.id.hasPrefix(machine.rawValue + "."), parameter.id)
                }
            }
        }
    }

    func testJSONParametersMirrorTheSwiftCatalog() throws {
        let doc = try loadDoc()
        XCTAssertEqual(Set(doc.parameters.map(\.id)), Set(everyParameter.map(\.id)))
        XCTAssertEqual(doc.parameters.count, Set(doc.parameters.map(\.id)).count, "duplicate ids in JSON")
        for entry in doc.parameters {
            let parameter = try param(entry.id)
            XCTAssertEqual(parameter.page.rawValue, entry.page, entry.id)
            XCTAssertEqual(parameter.slot, entry.slot, entry.id)
            XCTAssertEqual(parameter.knobLetter, entry.knob, entry.id)
            XCTAssertEqual(parameter.label, entry.label, entry.id)
            XCTAssertEqual(parameter.name, entry.name, entry.id)
            XCTAssertEqual(parameter.cc, entry.cc, entry.id)
            XCTAssertEqual(parameter.nrpn, entry.nrpn, entry.id)
            XCTAssertEqual(parameter.defaultValue, entry.default, entry.id)
            XCTAssertEqual(parameter.isHighResolution, entry.highResolution, entry.id)
            XCTAssertEqual(format(parameter.format), entry.format, entry.id)
            XCTAssertEqual(parameter.page.isGlobal, entry.scope == "global", entry.id)
            XCTAssertFalse(entry.source.isEmpty, entry.id)
            if parameter.page.isGlobal { continue }
            for machine in DNMachine.allCases {
                let present = HardwareCatalog.parameters(for: machine).contains(parameter)
                XCTAssertEqual(present, entry.machines.contains(machine.rawValue), "\(entry.id) on \(machine.title)")
            }
        }
    }

    // MARK: Values the manual states

    func testValueFormatsTakenFromTheManual() throws {
        XCTAssertEqual(try param("fmTone.syn1.algo").format, .number(1...8, offset: 1))
        XCTAssertEqual(try param("comp.ratio").format,
                       .options(["1.50", "2.00", "3.00", "4.00", "6.00", "8.00", "16.00", "20.00"]))
        XCTAssertEqual(try param("mod1.wave").format, .options(["TRI", "SINE", "SQR", "SAW", "EXPO", "RAMP", "RAND"]))
        XCTAssertEqual(try param("mod3.mode").format, .options(["FREE", "TRIG", "HOLD", "ONE", "HALF"]))
        XCTAssertEqual(try param("mod1.mode").defaultValue, 0, "FREE is the stated default")
        XCTAssertEqual(try param("fltr2.reset").defaultValue, 1, "RSET ON is the stated default")
        XCTAssertEqual(try param("amp.reset").defaultValue, 1, "RSET ON is the stated default")
        XCTAssertEqual(try param("mixer.patternVolume").defaultValue, 100, "100 = unity gain")
        XCTAssertEqual(try param("wavetone.syn3.noiseType").format, .options(["GRAIN", "TUNED", "S&H"]))
        XCTAssertEqual(try param("swarmer.syn1.mainOctave").format, .options(["0", "-1", "-2"]))
        XCTAssertTrue(try param("fmTone.syn1.harm").isHighResolution)
        XCTAssertTrue(try param("delay.time").isHighResolution)
        XCTAssertNil(try param("mod3.spd").cc, "LFO 3 has no CC")
        XCTAssertNil(try param("trig.fltTrig").nrpn, "Filter Trig has no NRPN")
    }

    func testFilterKnobsFAndGStayGeneric() throws {
        XCTAssertEqual(try param("fltr1.f").label, "F")
        XCTAssertEqual(try param("fltr1.g").label, "G")
        let machines = try loadDoc().filterMachines
        XCTAssertEqual(machines.map(\.machine), ["MULTI-MODE", "LOWPASS 4", "LEGACY LP/HP", "COMB-", "COMB+", "EQUALIZER"])
        XCTAssertEqual(machines.map(\.F), ["RESO", "RESO", "RESO", "FDBK", "FDBK", "GAIN"])
        XCTAssertEqual(machines.map(\.G), ["TYPE", nil, "TYPE", "LPF", "LPF", "Q"])
    }

    func testLFODestinationsFollowAppendixD() throws {
        func destinations(_ machine: DNMachine, _ page: DNPage) throws -> [String] {
            let dest = try XCTUnwrap(HardwareCatalog.parameters(on: page, machine: machine).first { $0.slot == 3 })
            XCTAssertEqual(dest.id, "\(machine.rawValue).\(page.rawValue).dest")
            guard case .options(let labels) = dest.format else { XCTFail("DEST is not a list"); return [] }
            return labels
        }
        let lfo1 = try destinations(.fmTone, .mod1)
        XCTAssertEqual(lfo1.first, "NONE")
        XCTAssertTrue(lfo1.contains("SYN DTUN"), "as on the MOD page screenshot")
        XCTAssertFalse(lfo1.contains { $0.hasPrefix("LFO") }, "LFO 1 cannot modulate LFOs")
        XCTAssertEqual(lfo1.suffix(7), ["FX DEL", "FX REV", "FX CHR", "FX BR", "FX SRR", "FX SR.RT", "FX OVER"])
        let lfo3 = try destinations(.swarmer, .mod3)
        XCTAssertTrue(lfo3.contains("LFO1 SPD") && lfo3.contains("LFO2 DEP"))
        XCTAssertEqual(lfo3.filter { $0.hasPrefix("SYN ") }.count, 8)
        let midi = try destinations(.midi, .mod2)
        XCTAssertEqual(midi, ["NONE", "LFO1 SPD", "LFO1 MULT", "LFO1 FADE", "LFO1 WAVE", "LFO1 SPH", "LFO1 MODE", "LFO1 DEP",
                              "SYN PB", "SYN AT", "SYN MW", "SYN BC"] + (1...16).map { "CC VAL\($0)" })
        let doc = try loadDoc()
        for machine in DNMachine.allCases {
            for page in HardwareCatalog.pages(for: machine) where page.rawValue.hasPrefix("mod") {
                XCTAssertEqual(doc.lfoDestinations["\(machine.rawValue).lfo\(page.rawValue.suffix(1))"],
                               try destinations(machine, page), "\(machine.title) \(page.title)")
            }
        }
    }

    func testFactoryChannels() throws {
        let channels = HardwareCatalog.factoryChannels
        XCTAssertEqual((0..<16).map { channels.channel(forTrack: $0) }, (0..<16).map { Optional($0) })
        XCTAssertNil(channels.channel(forTrack: 16))
        XCTAssertNil(channels.fxControlChannel)
        XCTAssertEqual(channels.autoChannel, 9)
        XCTAssertEqual(channels.effectiveProgramChangeChannel, 9)
        let doc = try loadDoc().factoryChannels
        XCTAssertEqual(doc.trackChannels, channels.trackChannels.map { ($0 ?? -1) + 1 })
        XCTAssertEqual(doc.autoChannel, channels.autoChannel + 1)
        XCTAssertNil(doc.fxControlChannel)
        XCTAssertEqual(doc.programChangeInChannel, "AUTO")
    }

    // MARK: Incoming events

    func testMatchResolvesIncomingEvents() {
        func id(cc: Int? = nil, nrpn: Int? = nil, _ machine: DNMachine = .fmTone, global: Bool = false) -> String? {
            HardwareCatalog.match(cc: cc, nrpn: nrpn, machine: machine, global: global)?.id
        }
        // Observed on the unit: Frequency, FLTR · F and Filter Attack on the auto channel.
        XCTAssertEqual(id(cc: 16), "fltr1.freq")
        XCTAssertEqual(id(cc: 17), "fltr1.f")
        XCTAssertEqual(id(cc: 20), "fltr1.atk")
        // Same numbers mean different things per channel scope and machine.
        XCTAssertEqual(id(cc: 16, global: true), "chorus.depth")
        XCTAssertEqual(id(cc: 17, global: true), "mixer.masterOverdrive")
        XCTAssertEqual(id(cc: 70), "fmTone.syn4.offsetC")
        XCTAssertEqual(id(cc: 70, .fmDrum), "fmDrum.syn4.noiseHold")
        XCTAssertNil(id(cc: 70, .wavetone), "WAVETONE has three SYN pages")
        XCTAssertEqual(id(cc: 70, .midi), "midi.val1")
        XCTAssertEqual(id(nrpn: 128 + 60), "mod3.fade")
        XCTAssertEqual(id(nrpn: 128 + 60, .midi), "midi.val9")
        XCTAssertEqual(id(cc: 40, .swarmer), "swarmer.syn1.tune")
        XCTAssertEqual(id(cc: 40, .midi), "midi.syn1.channel")
        // NRPN wins over CC; CC 86 stays Decay, NRPN 1:33 is Sustain.
        XCTAssertEqual(id(cc: 86), "amp.dec")
        XCTAssertEqual(id(cc: 86, nrpn: 128 + 33), "amp.sus")
        XCTAssertEqual(id(cc: 85), "amp.hold")
        XCTAssertEqual(id(nrpn: 3 * 128 + 7), "trig.port")
        XCTAssertNil(id(nrpn: 3 * 128 + 7, .midi), "portamento is audio only")
        XCTAssertEqual(id(nrpn: 2 * 128 + 24, global: true), "mixer.patternVolume")
        XCTAssertEqual(id(cc: 105, .wavetone), "wavetone.mod1.dest")
        XCTAssertEqual(id(nrpn: 3 * 128 + 8), "euclid.pulses1")
        XCTAssertEqual(id(nrpn: 3 * 128 + 14, .midi), "euclid.mode")
        XCTAssertEqual(id(cc: 73, global: true), "mixer.inputRLevel")
        XCTAssertNil(id(cc: 119), "Pattern Volume is global only")
    }

    // MARK: Display

    func testSnapshotCatalogCoversTrackParametersAndPreservesLegacyIDs() throws {
        for machine in SynthMachine.allCases {
            let hardware = HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!)
            let definitions = ParameterCatalog.parameters(for: machine)
            XCTAssertEqual(Set(definitions.map(\.id)).count, definitions.count)
            for parameter in hardware {
                let definition = try XCTUnwrap(ParameterCatalog.definition(for: parameter, machine: machine), parameter.id)
                XCTAssertEqual(ParameterCatalog.hardwareParameter(for: definition, machine: machine), parameter)
            }
        }
        let frequency = try param("fltr1.freq")
        XCTAssertEqual(ParameterCatalog.definition(for: frequency, machine: .fmTone)?.id, "filter.frequency")
        let attack = try param("amp.atk")
        XCTAssertEqual(ParameterCatalog.definition(for: attack, machine: .fmTone)?.id, "amp.attack")
        XCTAssertNil(ParameterCatalog.definition(for: try param("delay.time"), machine: .fmTone))
    }

    func testDisplayCoversEveryFormatKind() throws {
        let display = HardwareCatalog.display
        XCTAssertEqual(display(0, .number(0...127)), "0")
        XCTAssertEqual(display(200, .number(0...127)), "127")
        XCTAssertEqual(display(-5, .number(0...127)), "0")
        XCTAssertEqual(display(0, .number(1...8, offset: 1)), "1")
        XCTAssertEqual(display(7, .number(1...8, offset: 1)), "8")
        XCTAssertEqual(display(40, .number(1...8, offset: 1)), "8")
        XCTAssertEqual(display(0, .bipolar), "-64")
        XCTAssertEqual(display(64, .bipolar), "0")
        XCTAssertEqual(display(127, .bipolar), "+63")
        XCTAssertEqual(display(0, .toggle), "OFF")
        XCTAssertEqual(display(1, .toggle), "ON")
        XCTAssertEqual(display(127, .toggle), "ON")
        XCTAssertEqual(display(1, .options(["PRE", "POST"])), "POST")
        XCTAssertEqual(display(9, .options(["PRE", "POST"])), "POST")
        XCTAssertEqual(display(5, .options([])), "5")
        XCTAssertEqual(display(127, .scaled(min: 0, max: 100, decimals: 0, unit: "%")), "100 %")
        XCTAssertEqual(display(0, .scaled(min: 0, max: 1, decimals: 2, unit: "")), "0.00")

        // Catalog formats render like the device screen.
        func shown(_ id: String, _ value: Int) throws -> String { HardwareCatalog.display(value, format: try param(id).format) }
        XCTAssertEqual(try shown("trig.note", 60), "C5")
        XCTAssertEqual(try shown("trig.note", 127), "G10")
        XCTAssertEqual(try shown("trig.note", 0), "C0")
        XCTAssertEqual(try shown("fmTone.syn1.harm", 64), "0.00")
        XCTAssertEqual(try shown("fmTone.syn1.harm", 0), "-26.00")
        XCTAssertEqual(try shown("mod1.dep", 64), "0.00")
        XCTAssertEqual(try shown("mod1.dep", 0), "-64.00")
        XCTAssertEqual(try shown("delay.time", 0), "1")
        XCTAssertEqual(try shown("delay.time", 127), "128")
        XCTAssertEqual(try shown("amp.hold", 126), "126")
        XCTAssertEqual(try shown("amp.hold", 127), "NOTE")
        XCTAssertEqual(try shown("fmDrum.syn3.decay", 127), "INF")
        XCTAssertEqual(try shown("fmDrum.syn3.phaseC", 90), "90")
        XCTAssertEqual(try shown("fmDrum.syn3.phaseC", 91), "OFF")
        XCTAssertEqual(try shown("comp.ratio", 7), "20.00")
        XCTAssertEqual(try shown("mod2.mult", 1), "BPM 2")
        XCTAssertEqual(try shown("midi.syn1.channel", 0), "OFF")
        XCTAssertEqual(try shown("midi.syn1.channel", 16), "16")
        XCTAssertEqual(try shown("amp.pan", 64), "0")
    }
}
