import XCTest
import DigitoneCore
import DigitoneMIDI
@testable import DigitoneUI

/// Records what the control surface would send to the device.
@MainActor
private final class RecordingOutput: ControlOutput {
    var isAvailable = true
    var messages: [ControlMessage] = []
    var notes: [String] = []
    var rejectsMessages = false
    func send(_ message: ControlMessage) throws {
        if rejectsMessages { throw NSError(domain: "ControlTest", code: 1) }
        messages.append(message)
    }
    func noteOn(channel: Int, note: Int, velocity: Int) { notes.append("on \(channel) \(note) \(velocity)") }
    func noteOff(channel: Int, note: Int) { notes.append("off \(channel) \(note)") }
}

/// Channel routing, feedback, rate limiting, mutes, patterns and persistence of `ControlModel`.
@MainActor
final class ControlModelTests: XCTestCase {
    private static let attack = DNParameter(id: "t.fltr.atk", page: .fltr1, slot: 0, label: "ATK", name: "Attack", cc: 20, nrpn: 128 + 16)
    private static let decay = DNParameter(id: "t.fltr.dec", page: .fltr1, slot: 1, label: "DEC", name: "Decay", cc: 21, nrpn: 128 + 17)
    private static let frequency = DNParameter(id: "t.fltr.freq", page: .fltr1, slot: 4, label: "FREQ", name: "Frequency",
                                               cc: 16, nrpn: 128 + 20, isHighResolution: true)
    private static let mute = DNParameter(id: "t.mute", page: .track, slot: 0, label: "MUTE", name: "Mute", cc: 94,
                                          nrpn: 128 + 108, format: .toggle)
    private static let delayTime = DNParameter(id: "t.delay.time", page: .delay, slot: 0, label: "TIME", name: "Delay Time",
                                               cc: 21, nrpn: 256)
    private static let algorithm = DNParameter(id: "t.fmTone.algo", page: .syn1, slot: 0, label: "ALGO", name: "Algorithm",
                                               cc: 40, nrpn: 128 + 73, format: .number(1...8, offset: 1))
    private static let tune = DNParameter(id: "t.wavetone.tun1", page: .syn1, slot: 0, label: "TUN1", name: "Tune 1",
                                          cc: 40, nrpn: 128 + 73, format: .bipolar, defaultValue: 64)

    private static let catalog = ControlCatalog.fixed(
        pages: { _ in [.trig, .syn1, .fltr1, .amp, .track] },
        shared: [attack, decay, frequency, mute, delayTime],
        machineParameters: [.fmTone: [algorithm], .wavetone: [tune]])

    /// Tracks on channels 1...16 except track 3 (OFF), FX CONTROL CH 16, AUTO CHANNEL 10, program change on AUTO.
    private static let channels = DNChannelMap(trackChannels: (0..<16).map { $0 == 2 ? nil : $0 },
                                               fxControlChannel: 15, autoChannel: 9, programChangeChannel: nil)

    private var clock = 100.0
    private var output: RecordingOutput!

    private func makeModel(channels: DNChannelMap = ControlModelTests.channels, defaults: UserDefaults? = nil) -> ControlModel {
        output = RecordingOutput()
        return ControlModel(output: output, catalog: Self.catalog, defaults: defaults, channels: channels, now: { [unowned self] in self.clock })
    }

    private func cc(_ channel: Int, _ controller: Int, _ value: Int) -> ParameterEvent {
        var decoder = NRPNDecoder()
        return decoder.receive(channel: channel, cc: controller, value: value)!
    }

    private func nrpn(_ channel: Int, _ number: Int, _ value14: Int) -> ParameterEvent {
        var decoder = NRPNDecoder()
        _ = decoder.receive(channel: channel, cc: 99, value: number >> 7)
        _ = decoder.receive(channel: channel, cc: 98, value: number & 127)
        _ = decoder.receive(channel: channel, cc: 6, value: value14 >> 7)
        return decoder.receive(channel: channel, cc: 38, value: value14 & 127)!
    }

    // MARK: Sending

    func testTrackParametersGoToTheTrackChannelAndGlobalPagesToFXControl() {
        let model = makeModel()
        model.selectTrack(5)
        model.set(Self.attack, to: 90 << 7)
        XCTAssertEqual(output.messages, [.nrpn(channel: 5, parameter: 144, value: 90 << 7)])
        XCTAssertEqual(model.value(Self.attack), ControlValue(value: 90 << 7, origin: .sent))

        model.select(page: .delay)
        model.set(Self.delayTime, to: 32 << 7)
        XCTAssertEqual(output.messages.last, .nrpn(channel: 15, parameter: 256, value: 32 << 7))
        XCTAssertEqual(model.values[ControlKey(scope: .global, id: Self.delayTime.id)]?.origin, .sent)
    }

    func testChannelOffKeepsEditableDraftsAndDisablesSending() {
        let model = makeModel()
        model.selectTrack(2)
        XCTAssertTrue(model.canEdit(.fltr1))
        model.set(Self.attack, to: 10 << 7)
        model.toggleMute(track: 2)
        model.noteOn(60, velocity: 100)
        XCTAssertTrue(output.messages.isEmpty)
        XCTAssertTrue(output.notes.isEmpty)
        XCTAssertEqual(model.value(Self.attack), ControlValue(value: 10 << 7, origin: .draft))
        XCTAssertFalse(model.canApplyDrafts)

        let noFX = makeModel(channels: DNChannelMap(trackChannels: (0..<16).map { $0 }, fxControlChannel: nil,
                                                    autoChannel: 9, programChangeChannel: nil))
        XCTAssertTrue(noFX.canEdit(.delay))
        XCTAssertTrue(noFX.canEdit(.fltr1))
        noFX.set(Self.delayTime, to: 5 << 7)
        XCTAssertTrue(output.messages.isEmpty)

        output.isAvailable = false
        XCTAssertTrue(noFX.canEdit(.fltr1), "disconnected sound authoring remains available")
    }

    func testOfflineEditsAreClampedDraftsAndRequireExplicitApplyAfterConnection() async {
        let model = makeModel()
        output.isAvailable = false
        model.set(Self.frequency, to: 66 << 7 | 37)
        model.set(Self.attack, to: 20000)
        model.endEdit(Self.frequency)
        XCTAssertEqual(model.value(Self.frequency), ControlValue(value: 66 << 7 | 37, origin: .draft))
        XCTAssertEqual(model.value(Self.attack), ControlValue(value: 127 << 7, origin: .draft))
        XCTAssertTrue(output.messages.isEmpty)

        output.isAvailable = true
        model.flushAll()
        model.receive(nrpn(0, 148, 20 << 7))
        XCTAssertEqual(model.value(Self.frequency)?.value, 66 << 7 | 37, "reconnect feedback cannot silently replace an intentional draft")
        XCTAssertTrue(output.messages.isEmpty, "reconnecting does not apply offline changes")
        XCTAssertTrue(model.canApplyDrafts)
        await model.applyDrafts()
        XCTAssertEqual(output.messages, [.nrpn(channel: 0, parameter: 144, value: 127 << 7), .nrpn(channel: 0, parameter: 148, value: 66 << 7 | 37)])
        XCTAssertEqual(model.value(Self.frequency)?.origin, .sent)
        XCTAssertEqual(model.value(Self.attack)?.origin, .sent)
        XCTAssertFalse(model.canApplyDrafts)
        model.receive(nrpn(0, 148, 66 << 7 | 37))
        XCTAssertEqual(model.value(Self.frequency)?.origin, .received, "successful send is distinct from hardware readback")
    }

    func testStagingWhileConnectedCancelsQueuedGestureAndNeverWritesUntilApply() async {
        let model = makeModel()
        model.set(Self.frequency, to: 1000)
        clock += 0.001
        model.set(Self.frequency, to: 2000)
        model.stage([Self.frequency: 3333])
        model.flushAll()
        XCTAssertEqual(output.messages, [.nrpn(channel: 0, parameter: 148, value: 1000)])
        XCTAssertEqual(model.value(Self.frequency), ControlValue(value: 3333, origin: .draft))
        model.receive(nrpn(0, 148, 1000))
        XCTAssertEqual(model.value(Self.frequency)?.value, 3333)
        await model.applyDrafts()
        XCTAssertEqual(output.messages.last, .nrpn(channel: 0, parameter: 148, value: 3333))
    }

    func testExplicitApplySeparatesTrackSoundAndGlobalEffects() async {
        let model = makeModel()
        model.stage([Self.attack: 30 << 7, Self.delayTime: 40 << 7])
        model.select(page: .delay)
        await model.applyDrafts()
        XCTAssertEqual(output.messages, [.nrpn(channel: 15, parameter: 256, value: 40 << 7)])
        XCTAssertEqual(model.value(Self.attack)?.origin, .draft)
        XCTAssertEqual(model.value(Self.delayTime)?.origin, .sent)

        model.select(page: .fltr1)
        await model.applyDrafts()
        XCTAssertEqual(output.messages.last, .nrpn(channel: 0, parameter: 144, value: 30 << 7))
        XCTAssertEqual(model.value(Self.attack)?.origin, .sent)
    }

    func testStarterRecipesUseKnownBoundedTrackParametersAndRemainLocal() {
        let hardwareOutput = RecordingOutput()
        let model = ControlModel(output: hardwareOutput, defaults: nil)
        for starter in SoundStarter.all {
            XCTAssertEqual(starter.parameters.count, starter.coarseValues.count, "every recipe key must exist in the selected machine catalog")
            for (parameter, value) in starter.parameters {
                XCTAssertFalse(parameter.page.isGlobal)
                XCTAssertEqual(value, ControlEncoding.clamp(value, for: parameter))
            }
            model.stageSound(starter)
            XCTAssertEqual(model.machine, starter.machine)
            XCTAssertTrue(starter.parameters.allSatisfy { model.value($0.key)?.origin == .draft })
        }
        XCTAssertTrue(hardwareOutput.messages.isEmpty, "a template stages a draft even when connected")
    }

    func testAssigningChannelToOfflineTrackPreservesDraftAndMakesItSaveable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-offline-route-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        output.isAvailable = false
        let model = ControlModel(output: output, defaults: nil)
        model.bind(to: studio)
        model.setTrackChannel(nil, track: 0)
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        model.set(frequency, to: 66 << 7 | 37)
        model.setTrackChannel(4, track: 0)
        XCTAssertEqual(model.selectedTrack, 0)
        XCTAssertEqual(studio.channel, 4)
        XCTAssertEqual(model.value(frequency), ControlValue(value: 66 << 7 | 37, origin: .draft))
        XCTAssertEqual(studio.known["filter.frequency"], KnownParameter(value: 66, origin: .draft))
        XCTAssertTrue(output.messages.isEmpty)
        studio.snapshotName = "Offline route"
        studio.saveSnapshot()
        XCTAssertEqual(studio.snapshots.first?.parameters["filter.frequency"], 66)
    }

    func testEveryHardwareSoundParameterRoundTripsThroughLibraryDefinitions() throws {
        for synth in SynthMachine.allCases {
            let machine = try XCTUnwrap(DNMachine(rawValue: synth.rawValue))
            for hardware in HardwareCatalog.parameters(for: machine) {
                let definition = try XCTUnwrap(ParameterCatalog.definition(for: hardware, machine: synth), "\(synth.title): \(hardware.id) must be saveable")
                XCTAssertEqual(ParameterCatalog.hardwareParameter(for: definition, machine: synth)?.id, hardware.id,
                               "\(synth.title): \(hardware.id) must load to the same parameter")
            }
        }
    }

    func testDragIsCoalescedAndTheFinalValueAlwaysArrives() {
        let model = makeModel()
        model.set(Self.frequency, to: 1000)
        clock += 0.004; model.set(Self.frequency, to: 1100)
        clock += 0.004; model.set(Self.frequency, to: 1234)
        XCTAssertEqual(output.messages.count, 1, "one message per 1/60 s")
        XCTAssertEqual(model.value(Self.frequency)?.value, 1234, "the screen shows the newest value at once")

        clock += 0.010
        model.flushDue()
        XCTAssertEqual(output.messages, [.nrpn(channel: 0, parameter: 148, value: 1000), .nrpn(channel: 0, parameter: 148, value: 1234)])

        clock += 0.001; model.set(Self.frequency, to: 1300)
        clock += 0.001; model.set(Self.frequency, to: 1301)
        model.endEdit(Self.frequency)
        XCTAssertEqual(output.messages.last, .nrpn(channel: 0, parameter: 148, value: 1301), "gesture end delivers the final value")
        let count = output.messages.count
        model.set(Self.frequency, to: 1301)
        XCTAssertEqual(output.messages.count, count, "an unchanged value is not resent")
    }

    // MARK: Feedback

    func testFeedbackOnTrackChannelsMarksValuesReceived() {
        let model = makeModel()
        model.receive(cc(7, 20, 77))
        XCTAssertEqual(model.values[ControlKey(scope: .track(7), id: Self.attack.id)], ControlValue(value: 77 << 7, origin: .received))
        XCTAssertTrue(model.feedbackSeen)

        model.receive(nrpn(4, 148, 99 << 7 | 12))
        XCTAssertEqual(model.values[ControlKey(scope: .track(4), id: Self.frequency.id)]?.value, 99 << 7 | 12)

        model.inputRouting = .trackChannel
        model.receive(cc(9, 20, 33))
        XCTAssertEqual(model.values[ControlKey(scope: .track(9), id: Self.attack.id)]?.value, 33 << 7,
                       "a channel that is a track channel addresses that track")
    }

    func testFeedbackOnFXControlChannelIsGlobal() {
        let model = makeModel()
        model.receive(cc(15, 21, 64))
        XCTAssertEqual(model.values[ControlKey(scope: .global, id: Self.delayTime.id)]?.value, 64 << 7)
        XCTAssertNil(model.values[ControlKey(scope: .track(15), id: Self.decay.id)], "CC 21 on FX CONTROL CH is DELAY TIME, not FLTR DEC")
        model.receive(cc(1, 21, 64))
        XCTAssertEqual(model.values[ControlKey(scope: .track(1), id: Self.decay.id)]?.value, 64 << 7)
    }

    func testFeedbackOnAutoChannelGoesToTheSelectedTrack() {
        var map = Self.channels
        map.trackChannels[9] = nil
        let model = makeModel(channels: map)
        model.selectTrack(11)
        model.receive(cc(9, 20, 12))
        XCTAssertEqual(model.values[ControlKey(scope: .track(11), id: Self.attack.id)]?.value, 12 << 7)
        model.receive(cc(2, 20, 5))
        XCTAssertNil(model.values.first { $0.value.value == 5 << 7 }, "channel 3 belongs to no track")
    }

    func testFeedbackResolvesMachineDependentParameters() {
        let model = makeModel()
        model.setMachine(.wavetone, track: 1)
        model.receive(cc(0, 40, 3))
        model.receive(cc(1, 40, 70))
        XCTAssertEqual(model.values[ControlKey(scope: .track(0), id: Self.algorithm.id)]?.value, 3 << 7)
        XCTAssertEqual(model.values[ControlKey(scope: .track(1), id: Self.tune.id)]?.value, 70 << 7)
    }

    func testPendingLocalEditIsNotOverwrittenByOlderFeedback() {
        let model = makeModel()
        model.set(Self.frequency, to: 1000)
        clock += 0.002; model.set(Self.frequency, to: 2000)
        model.receive(nrpn(0, 148, 1000))
        XCTAssertEqual(model.value(Self.frequency), ControlValue(value: 2000, origin: .draft))
    }

    // MARK: Mutes, patterns, transport, keys

    func testMuteSendsCC94AndFollowsTheDevice() {
        let model = makeModel()
        model.toggleMute(track: 4)
        XCTAssertEqual(output.messages.last?.bytes, [0xb4, 94, 127])
        XCTAssertEqual(model.mute(track: 4), Observed(value: true, origin: .sent))
        model.toggleMute(track: 4)
        XCTAssertEqual(output.messages.last?.bytes, [0xb4, 94, 0])

        model.receive(cc(6, 94, 127))
        XCTAssertEqual(model.mute(track: 6), Observed(value: true, origin: .received))

        model.selectTrack(7)
        model.select(page: .track)
        model.set(Self.mute, to: 127 << 7)
        XCTAssertEqual(output.messages.last, .cc(channel: 7, controller: 94, value: 127), "the MUTE knob uses the same CC")
    }

    func testPatternSelectionSendsProgramChangeAndFollowsTheDevice() {
        let model = makeModel()
        model.selectPattern(ControlEncoding.program(bank: 2, pattern: 4))
        XCTAssertEqual(output.messages.last, .programChange(channel: 9, program: 36), "AUTO → auto channel")
        XCTAssertEqual(model.program, Observed(value: 36, origin: .sent))
        model.setProgramChannel(3)
        model.selectPattern(0)
        XCTAssertEqual(output.messages.last?.bytes, [0xc3, 0])

        model.receive(MIDIInputEvent.programChange(channel: 3, program: 17))
        XCTAssertEqual(model.program, Observed(value: 17, origin: .received))
        model.receive(MIDIInputEvent.programChange(channel: 12, program: 99))
        XCTAssertEqual(model.program?.value, 17, "other channels are not pattern changes")
    }

    func testTransportStartStopAndIncomingState() {
        let model = makeModel()
        model.togglePlay()
        XCTAssertEqual(output.messages, [.start])
        XCTAssertEqual(model.transport, Observed(value: true, origin: .sent))
        model.togglePlay()
        XCTAssertEqual(output.messages, [.start, .stop])
        model.receive(MIDIInputEvent.transport(.start))
        XCTAssertEqual(model.transport, Observed(value: true, origin: .received))
    }

    func testKeyboardPlaysTheSelectedTrackAndReleasesOnTrackChange() {
        let model = makeModel()
        model.selectTrack(3)
        model.noteOn(60, velocity: 100)
        model.noteOn(64, velocity: 90)
        XCTAssertEqual(model.heldNotes, [60, 64])
        model.selectTrack(4)
        XCTAssertEqual(Array(output.notes.prefix(2)), ["on 3 60 100", "on 3 64 90"])
        XCTAssertEqual(Set(output.notes.suffix(2)), ["off 3 60", "off 3 64"], "held notes end on their own channel")
        XCTAssertTrue(model.heldNotes.isEmpty)

        model.receive(MIDIInputEvent.note(MIDINoteEvent(channel: 4, note: 48, velocity: 80, isOn: true, hostTime: 0)))
        XCTAssertEqual(model.incomingNotes, [48])
    }

    func testDisconnectForgetsDeviceState() {
        let model = makeModel()
        model.receive(cc(0, 20, 1))
        model.selectPattern(3)
        model.connectionEnded()
        XCTAssertTrue(model.values.isEmpty)
        XCTAssertNil(model.program)
        XCTAssertNil(model.transport)
    }

    func testFactoryAutoOutputFollowsSelectedTrackAndTrackModeIsExplicit() {
        let model = makeModel(channels: HardwareCatalog.factoryChannels)
        model.receive(cc(9, 20, 70))
        XCTAssertEqual(model.values[ControlKey(scope: .track(0), id: Self.attack.id)]?.value, 70 << 7)
        XCTAssertNil(model.values[ControlKey(scope: .track(9), id: Self.attack.id)], "AUTO output from the selected track is not track 10 feedback")
        model.inputRouting = .trackChannel
        model.receive(cc(9, 20, 80))
        XCTAssertEqual(model.values[ControlKey(scope: .track(9), id: Self.attack.id)]?.value, 80 << 7)
    }

    func testFailedSendRetainsDraftAndDoesNotClaimTransportOrPattern() {
        let model = makeModel()
        output.rejectsMessages = true
        model.set(Self.frequency, to: 1234)
        XCTAssertEqual(model.value(Self.frequency), ControlValue(value: 1234, origin: .draft))
        model.start()
        model.selectPattern(19)
        XCTAssertNil(model.transport)
        XCTAssertNil(model.program)
        XCTAssertTrue(output.messages.isEmpty)
    }

    func testHardwareFeedbackPreservesValuesBeyondAnAssumedOptionList() {
        let model = makeModel()
        model.receive(cc(0, 40, 100))
        XCTAssertEqual(model.value(Self.algorithm)?.value, 100 << 7, "instrument feedback is authoritative even when a display list differs")
    }

    func testLegacySoundLoadsAsDraftAndReplacingItRemovesObsoleteKnobs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-bridge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        let control = ControlModel(output: output, defaults: nil)
        control.bind(to: studio)
        let first = SoundSnapshot(name: "Legacy", machine: .fmTone, channel: 4,
                                  parameters: ["syn.1.a": 3, "filter.frequency": 70])
        studio.load(first)
        XCTAssertEqual(control.selectedTrack, 4)
        XCTAssertEqual(control.machine, .fmTone)
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        XCTAssertEqual(control.value(frequency), ControlValue(value: 70 << 7, origin: .draft))
        XCTAssertTrue(output.messages.isEmpty, "loading a saved sound must not write MIDI")

        let second = SoundSnapshot(name: "New", machine: .wavetone, channel: 4, parameters: ["syn.1.a": 64])
        studio.load(second)
        XCTAssertEqual(control.machine, .wavetone, "the loaded snapshot changes the app's machine label")
        XCTAssertNil(control.value(frequency), "a replacement snapshot must not retain a previous filter knob")
        let tune = try XCTUnwrap(HardwareCatalog.parameters(on: .syn1, machine: .wavetone).first { $0.slot == 0 })
        XCTAssertEqual(control.value(tune)?.origin, .draft)
        XCTAssertEqual(control.value(tune)?.value, 64 << 7)
        XCTAssertTrue(output.messages.isEmpty)
    }

    func testFineNRPNAndFullCatalogSendsEnterCoarseSoundSnapshotsWithoutFX() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        let control = ControlModel(output: output, defaults: nil)
        control.bind(to: studio)
        control.setFXChannel(15)
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        control.receive(nrpn(0, frequency.nrpn!, 70 << 7 | 51))
        XCTAssertEqual(control.value(frequency)?.value, 70 << 7 | 51, "coarse archive mirroring must retain fine steps in the live model")
        XCTAssertEqual(studio.known["filter.frequency"]?.value, 70)
        XCTAssertEqual(studio.known["filter.frequency"]?.origin, .received)
        let modulation = try XCTUnwrap(HardwareCatalog.parameter(id: "mod3.spd"))
        control.set(modulation, to: 82 << 7)
        XCTAssertEqual(studio.known[modulation.id]?.value, 82, "parameters beyond the old SYN1 editor enter sound snapshots")
        XCTAssertEqual(studio.known[modulation.id]?.origin, .sent)
        let knownBeforeFX = studio.known.count
        let delay = try XCTUnwrap(HardwareCatalog.parameters(on: .delay, machine: .fmTone).first { $0.label == "TIME" })
        control.receive(cc(15, delay.cc!, 42))
        XCTAssertEqual(studio.known.count, knownBeforeFX, "global effects must never contaminate a track sound archive")
        XCTAssertNil(studio.known[delay.id])
        studio.snapshotName = "Bridge"
        studio.saveSnapshot()
        XCTAssertEqual(studio.snapshots.first?.parameters[modulation.id], 82)
        XCTAssertEqual(studio.snapshots.first?.parameters["filter.frequency"], 70)
    }

    func testAppliedCoarseDraftOriginIsReflectedWithoutSendingAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-apply-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        let control = ControlModel(output: output, defaults: nil)
        control.bind(to: studio)
        studio.load(SoundSnapshot(name: "Draft", machine: .fmTone, channel: 0, parameters: ["filter.frequency": 66]))
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        XCTAssertEqual(control.value(frequency)?.origin, .draft)
        // StudioModel.apply marks each successful transfer sent; the bridge follows that result.
        studio.values[studio.route]?["filter.frequency"] = KnownParameter(value: 66, origin: .sent)
        XCTAssertEqual(control.value(frequency)?.origin, .sent)
        XCTAssertFalse(control.hasDrafts)
        XCTAssertTrue(output.messages.isEmpty, "observing an apply result must not trigger another hardware write")
    }

    func testApplyingFineDraftPreservesFineStepsButLoadingAnArchiveResetsThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-fine-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        let control = ControlModel(output: output, defaults: nil)
        control.bind(to: studio)
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        output.rejectsMessages = true
        control.set(frequency, to: 66 << 7 | 37)
        XCTAssertEqual(control.value(frequency)?.origin, .draft)
        studio.values[studio.route]?["filter.frequency"] = KnownParameter(value: 66, origin: .sent)
        XCTAssertEqual(control.value(frequency), ControlValue(value: 66 << 7 | 37, origin: .sent))

        control.set(frequency, to: 66 << 7 | 52)
        control.endEdit(frequency)
        XCTAssertEqual(control.value(frequency)?.origin, .draft)
        control.prepareSoundDraftReplacement()
        studio.values[studio.route] = ["filter.frequency": KnownParameter(value: 66, origin: .draft)]
        XCTAssertEqual(control.value(frequency), ControlValue(value: 66 << 7, origin: .draft), "an archive has coarse values even when a live draft had the same coarse value")
    }

    func testPatternChangesInvalidateObservedSoundAndFXButKeepDrafts() {
        let model = makeModel()
        model.receive(cc(0, 20, 75))
        model.receive(cc(15, 21, 45))
        output.rejectsMessages = true
        model.set(Self.frequency, to: 1234)
        model.selectPattern(17)
        XCTAssertNotNil(model.value(Self.attack), "a failed program request keeps the known current sound")
        XCTAssertNotNil(model.value(Self.delayTime))
        output.rejectsMessages = false
        model.selectPattern(17)
        XCTAssertNil(model.value(Self.attack))
        XCTAssertNil(model.value(Self.delayTime))
        XCTAssertEqual(model.value(Self.frequency)?.origin, .draft)
        model.receive(cc(0, 20, 25))
        model.selectPattern(17)
        XCTAssertEqual(model.value(Self.attack)?.value, 25 << 7, "requesting the same pattern does not discard feedback")
        model.receive(MIDIInputEvent.programChange(channel: 9, program: 17))
        XCTAssertNil(model.value(Self.attack), "the first actual confirmation clears feedback that may have arrived before the pattern boundary")
        model.receive(cc(0, 20, 26))
        model.receive(MIDIInputEvent.programChange(channel: 9, program: 17))
        XCTAssertEqual(model.value(Self.attack)?.value, 26 << 7, "repeating the same confirmed pattern keeps feedback")
        model.receive(MIDIInputEvent.programChange(channel: 9, program: 18))
        XCTAssertNil(model.value(Self.attack), "a different reported pattern invalidates the previous sound")
        XCTAssertEqual(model.value(Self.frequency)?.origin, .draft)
    }

    func testPatternChangeClearsObservedSoundArchiveValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-pattern-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let output = RecordingOutput()
        let control = ControlModel(output: output, defaults: nil)
        control.bind(to: studio)
        let frequency = try XCTUnwrap(HardwareCatalog.parameter(id: "fltr1.freq"))
        control.receive(nrpn(0, frequency.nrpn!, 70 << 7 | 51))
        XCTAssertEqual(studio.known["filter.frequency"]?.origin, .received)
        control.selectPattern(21)
        XCTAssertNil(studio.known["filter.frequency"])
        XCTAssertNil(control.value(frequency))
    }

    // MARK: Pages and persistence

    func testPagesFollowTheMachineAndGroupsCycle() {
        let model = makeModel()
        XCTAssertEqual(model.pages, [.trig, .syn1, .fltr1, .amp, .track])
        model.select(page: .fltr1)
        model.step(page: 1)
        XCTAssertEqual(model.page, .amp)
        model.step(page: -3)
        XCTAssertEqual(model.page, .trig)
        model.step(page: -1)
        XCTAssertEqual(model.page, .mixerRight, "global pages follow the track pages")
        model.select(group: "SYN")
        XCTAssertEqual(model.page, .syn1)
        XCTAssertEqual(DNPage.mod2.group, "MOD")
        XCTAssertEqual(DNPage.mod2.subpage, 2)
        XCTAssertNil(DNPage.compressor.subpage)
    }

    func testMachinesChannelsAndChecksPersist() throws {
        let suite = "digitone-control-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.setMachine(.swarmer, track: 5)
        model.setTrackChannel(nil, track: 0)
        model.setFXChannel(13)
        model.setAutoChannel(11)
        model.toggleCheck("sync.clock")
        model.selectTrack(5)

        let reopened = ControlModel(output: RecordingOutput(), catalog: Self.catalog, defaults: defaults)
        XCTAssertEqual(reopened.machines[5], .swarmer)
        XCTAssertEqual(reopened.machines[0], .fmTone)
        XCTAssertNil(reopened.channelMap.channel(forTrack: 0))
        XCTAssertEqual(reopened.channelMap.fxControlChannel, 13)
        XCTAssertEqual(reopened.channelMap.autoChannel, 11)
        XCTAssertEqual(reopened.setupChecks, ["sync.clock"])
        XCTAssertEqual(reopened.selectedTrack, 5)
    }

    func testStudioInputReachesTheSurfaceAndChannelSelectionFollowsTheStudio() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = StudioModel(directory: directory, startMIDI: false)
        let model = makeModel()
        model.bind(to: studio)
        studio.parameterInput.send(cc(3, 20, 50))
        XCTAssertEqual(model.values[ControlKey(scope: .track(3), id: Self.attack.id)]?.value, 50 << 7)
        studio.channel = 8
        XCTAssertEqual(model.selectedTrack, 8)
        model.selectTrack(12)
        XCTAssertEqual(studio.channel, 12)
    }
}
