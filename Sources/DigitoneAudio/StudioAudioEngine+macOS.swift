#if os(macOS)
import AudioToolbox
import AVFoundation
import CoreAudio

extension StudioAudioEngine {
    /// Output first (so pads keep playing whatever happens to the input), then input.
    func startPlatform(enableInput: Bool) throws {
        devices.refresh()
        if state != .running { try startOutput() }
        if enableInput, !isInputRunning { try startInput() }
    }

    // MARK: Output

    /// AVAudioEngine on the resolved output, never touching `engine.inputNode`:
    /// that would switch the engine to a hidden default-device aggregate and
    /// open the built-in microphone.
    func startOutput() throws {
        isRebuilding = true
        defer { isRebuilding = false }
        guard let device = resolveOutput() else {
            throw policy.pinnedOutputID != nil ? AudioEngineError.deviceMissing(pinnedOutputName ?? "выбранный аудиовыход")
                                               : AudioEngineError.noOutputDevice
        }
        guard let id = AudioDeviceDiscovery.deviceID(forUID: device.id) else { throw AudioEngineError.deviceMissing(device.name) }
        if outputDevice?.id != device.id { requestedOutputFrames = options.bufferFrames }
        outputDevice = device
        // Block an input → same-interface loop before the output starts, even
        // when the previous route was safe and the source kept its old gain.
        monitorBlock = policy.monitorBlock(input: isInputRunning ? inputDevice : resolveInput(), output: device, permission: permission)
        applyMonitoring()
        try setCurrentDevice(id, name: device.name, on: engine.outputNode)
        outputBufferFrames = AudioDeviceDiscovery.requestBufferFrameSize(requestedOutputFrames, on: id)
        outputOverloadToken = AudioDeviceDiscovery.observeOverloads(id) { [weak self] in self?.noteOverload(input: false) }
        try buildOutputGraph()
        ensureMonitorNode(sampleRate: inputFormat?.sampleRate ?? monitorSource?.sampleRate ?? DigitoneAudioModule.preferredSampleRate)
        engine.prepare()
        do { try engine.start() } catch {
            state = .stopped
            throw Self.wrap(error, "старт AVAudioEngine")
        }
        state = .running
        refreshLatency()
    }

    /// Rebuilds the output after a device or default-output change. Input keeps running.
    func restartOutput() {
        guard state == .running || state == .interrupted else { return }
        playback.stop()
        isPlaying = false
        engine.stop()
        monitorSource?.reprime()
        state = .stopped
        outputDevice = resolveOutput()
        do {
            try startOutput()
        } catch {
            lastError = Self.wrap(error, "перезапуск аудиовыхода")
        }
        refreshMonitor()
    }

    func engineConfigurationChanged() {
        // The engine stops itself when its device's format changes; the input unit is unaffected.
        guard state == .running, !isRebuilding, !engine.isRunning else { return }
        restartOutput()
    }

    // MARK: Input

    func startInput() throws {
        guard let device = resolveInput() else {
            throw policy.pinnedInputID != nil ? AudioEngineError.deviceMissing(pinnedInputName ?? "выбранный аудиовход")
                                              : AudioEngineError.noInputDevice
        }
        guard let id = AudioDeviceDiscovery.deviceID(forUID: device.id) else { throw AudioEngineError.deviceMissing(device.name) }
        let rate = device.nominalSampleRate ?? DigitoneAudioModule.preferredSampleRate
        guard rate.isFinite, rate > 0 else { throw AudioEngineError.formatUnsupported("частота аудиовхода") }
        let format = StreamFormat(sampleRate: rate, channelCount: min(max(device.inputChannels, 1), 2))
        checkRecordingFormat(format)
        if inputDevice?.id != device.id { requestedInputFrames = options.bufferFrames }
        inputFormat = format
        monitorBlock = policy.monitorBlock(input: device, output: outputDevice, permission: permission)
        applyMonitoring()
        pipeline.configure(format)
        inputBufferFrames = AudioDeviceDiscovery.requestBufferFrameSize(requestedInputFrames, on: id)
        if state == .running { ensureMonitorNode(sampleRate: rate) }
        do {
            monitorSource?.reprime()
            let unit = try HALInput(.init(deviceID: id, channelCount: format.channelCount, sampleRate: rate),
                                    ring: monitorRing, levels: inputMeter.tap, capture: pipeline.inputQueue)
            try unit.start()
            halInput = unit
        } catch {
            pipeline.stopInput()
            inputFormat = nil
            throw error
        }
        inputDevice = device
        isInputRunning = true
        inputOverloadToken = AudioDeviceDiscovery.observeOverloads(id) { [weak self] in self?.noteOverload(input: true) }
        inputFormatToken = AudioDeviceDiscovery.observeInputFormat(id) { [weak self] in self?.devices.refresh() }
        monitorSource?.setMinimumTarget(handoffTarget())
        refreshLatency()
        refreshMonitor()
    }

    /// Stops the input unit first, then drains the capture queue and closes the take.
    func stopInput(failure: AudioEngineError) {
        halInput?.dispose()
        halInput = nil
        inputOverloadToken = nil
        inputFormatToken = nil
        pipeline.stopInput()
        finishRecording()
        pipeline.failSegments(failure)
        if isInputRunning { isInputRunning = false }
        inputFormat = nil
        monitorLatency = nil
        monitorSource?.reprime()
    }

    func restartInput() throws {
        let previous = inputDevice
        stopInput(failure: .deviceMissing(previous?.name ?? "аудиовход"))
        inputDevice = resolveInput()
        if inputDevice?.id != previous?.id { pipeline.resetCapture() }
        try startInput()
    }

    // MARK: Monitor path

    /// The monitor node runs at the input rate; the main mixer converts to the output rate.
    func ensureMonitorNode(sampleRate: Double) {
        if let monitorSource, let monitorNode, monitorSource.sampleRate == sampleRate,
           engine.attachedNodes.contains(monitorNode) {
            if engine.outputConnectionPoints(for: monitorNode, outputBus: 0).isEmpty {
                engine.connect(monitorNode, to: engine.mainMixerNode, format: monitorNode.outputFormat(forBus: 0))
            }
            return
        }
        if let monitorNode {
            engine.disconnectNodeOutput(monitorNode)
            engine.detach(monitorNode)
        }
        let source = MonitorSource(ring: monitorRing, sampleRate: sampleRate, targetFill: 256)
        let node = MonitorSource.makeNode(for: source)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
        monitorSource = source
        monitorNode = node
        source.setMinimumTarget(handoffTarget())
        applyMonitoring()
    }

    func applyMonitoring() {
        monitorSource?.targetGain = monitorAudible ? monitorGain : 0
    }

    /// Input block plus half an output block (at the input rate) plus margin:
    /// the fill seen by the output sweeps by one input block as the two clocks
    /// slide past each other. Raised automatically after an underrun.
    func handoffTarget() -> Int {
        let inputRate = inputFormat?.sampleRate ?? DigitoneAudioModule.preferredSampleRate
        let outputRate = outputFormat?.sampleRate ?? inputRate
        let output = Double(max(outputBufferFrames, 64)) * inputRate / max(outputRate, 1)
        return max(inputBufferFrames, 64) + Int(output / 2) + 64
    }

    /// Updates `monitorLatency` from the HAL; call when the readout is shown.
    public func refreshLatency() {
        guard isInputRunning, state == .running,
              let input = inputDevice.flatMap({ AudioDeviceDiscovery.deviceID(forUID: $0.id) }),
              let output = outputDevice.flatMap({ AudioDeviceDiscovery.deviceID(forUID: $0.id) }) else {
            if monitorLatency != nil { monitorLatency = nil }
            return
        }
        inputBufferFrames = AudioDeviceDiscovery.bufferFrameSize(input)
        outputBufferFrames = AudioDeviceDiscovery.bufferFrameSize(output)
        let latency = MonitorLatency(input: AudioDeviceDiscovery.latency(input, input: true),
                                     handoffFrames: monitorSource?.targetFill ?? handoffTarget(),
                                     output: AudioDeviceDiscovery.latency(output, input: false))
        if latency != monitorLatency { monitorLatency = latency }
    }

    /// Counters from the input callback, the monitor reader and the ring.
    public func diagnostics() -> MonitorDiagnostics {
        var result = MonitorDiagnostics()
        if let halInput {
            result.inputCallbacks = halInput.clock.calls
            result.inputFrames = halInput.clock.frames
            result.inputRate = halInput.clock.rate
            result.inputRenderErrors = halInput.renderErrors
        }
        if let monitorSource {
            result.outputCallbacks = monitorSource.clock.calls
            result.outputFrames = monitorSource.clock.frames
            result.outputRate = monitorSource.clock.rate
            result.underruns = monitorSource.underruns
            result.resyncs = monitorSource.resyncs
            result.fill = monitorSource.lastFill
            result.targetFill = monitorSource.targetFill
            result.correctionPPM = monitorSource.correctionPPM
        }
        result.droppedInputBlocks = monitorRing.droppedWrites
        result.overloads = overloadCount
        return result
    }

    func enlargeBuffer(input: Bool) {
        if input, isInputRunning, let id = inputDevice.flatMap({ AudioDeviceDiscovery.deviceID(forUID: $0.id) }) {
            requestedInputFrames = min(max(requestedInputFrames, inputBufferFrames) * 2, 1_024)
            inputBufferFrames = AudioDeviceDiscovery.requestBufferFrameSize(requestedInputFrames, on: id)
        } else if !input, state == .running, let id = outputDevice.flatMap({ AudioDeviceDiscovery.deviceID(forUID: $0.id) }) {
            requestedOutputFrames = min(max(requestedOutputFrames, outputBufferFrames) * 2, 1_024)
            outputBufferFrames = AudioDeviceDiscovery.requestBufferFrameSize(requestedOutputFrames, on: id)
        }
        monitorSource?.setMinimumTarget(handoffTarget())
        refreshLatency()
    }

    // MARK: Routing changes

    func reroute(input: Bool) throws {
        if input {
            if isInputRunning {
                try restartInput()
            } else {
                inputDevice = resolveInput()
            }
        } else if state == .running {
            restartOutput()
            if state != .running, let lastError { throw lastError }
        } else {
            outputDevice = resolveOutput()
        }
    }

    /// Hot-plug and default-device changes: the output follows the system
    /// default; the input moves to a newly attached Digitone, stops gracefully
    /// when its device disappears, and starts by itself on a Digitone plug-in.
    func devicesChanged() {
        guard !isRebuilding else { return }
        if state == .running {
            if let current = outputDevice, devices.device(id: current.id) == nil || resolveOutput()?.id != current.id {
                restartOutput()
            }
        } else {
            outputDevice = resolveOutput()
            if autoStartArmed, isInputRunning, outputDevice != nil {
                do { try startOutput() } catch { lastError = Self.wrap(error, "подключение аудиовыхода") }
            }
        }
        if isInputRunning, let current = inputDevice {
            if devices.device(id: current.id) == nil {
                let wasRecording = pipeline.recorder.isRecording
                stopInput(failure: .deviceMissing(current.name))
                inputDevice = resolveInput()
                if wasRecording { lastError = .deviceMissing(current.name) }
            } else if let wanted = resolveInput() {
                let changedDevice = wanted.id != current.id && (wanted.isDigitone || policy.pinnedInputID != nil)
                let changedFormat = wanted.id == current.id
                    && ((wanted.nominalSampleRate ?? DigitoneAudioModule.preferredSampleRate) != inputFormat?.sampleRate
                        || min(max(wanted.inputChannels, 1), 2) != inputFormat?.channelCount)
                if changedDevice || changedFormat {
                    do { try restartInput() } catch { lastError = Self.wrap(error, "переключение аудиовхода") }
                }
            }
        } else {
            inputDevice = resolveInput()
            if autoStartArmed, permission == .granted, wantsAutomaticInput, startTask == nil {
                Task { await autoStart() }
            }
        }
        refreshMonitor()
        refreshLatency()
    }

    // MARK: HAL

    private func setCurrentDevice(_ id: AudioDeviceID, name: String, on node: AVAudioIONode) throws {
        guard let unit = node.audioUnit else { throw AudioEngineError.system("audioUnit", -1) }
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size) == noErr,
           current == id { return }
        var device = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw AudioEngineError.system("выбор устройства «\(name)»", status) }
    }
}
#endif
