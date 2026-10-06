#if os(iOS)
import AVFoundation

/// iOS: one engine on the session route. Input and output share the route's
/// clock, so the input node feeds the monitor mixer directly. A USB Digitone
/// takes over both directions; monitoring is then off (it would loop).
extension StudioAudioEngine {
    func startPlatform(enableInput: Bool) throws {
        if state == .running || state == .interrupted {
            guard enableInput, !isInputRunning else { return }
            teardownGraph()
        }
        inputRequested = enableInput
        do {
            try startGraph()
        } catch {
            teardownGraph()
            state = .stopped
            throw error
        }
    }

    func startGraph() throws {
        isRebuilding = true
        defer { isRebuilding = false }
        devices.refresh()
        try configureSession()
        inputDevice = resolveInput()
        outputDevice = resolveOutput()
        if inputRequested, policy.pinnedInputID != nil, inputDevice == nil {
            throw AudioEngineError.deviceMissing(pinnedInputName ?? "выбранный аудиовход")
        }
        try buildOutputGraph()
        if inputRequested { try buildInput() }
        engine.prepare()
        do { try engine.start() } catch { throw Self.wrap(error, "старт AVAudioEngine") }
        state = .running
        refreshMonitor()
        refreshLatency()
    }

    private func buildInput() throws {
        let input = engine.inputNode.inputFormat(forBus: 0)
        guard input.sampleRate.isFinite, input.sampleRate > 0, input.channelCount > 0 else {
            inputFormat = nil
            throw AudioEngineError.noInputDevice
        }
        let format = StreamFormat(sampleRate: input.sampleRate, channelCount: min(Int(input.channelCount), 2))
        checkRecordingFormat(format)
        inputFormat = format
        pipeline.configure(format)
        // An explicit client format: the tap must not inherit a stale channel count.
        let client = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: AVAudioChannelCount(format.channelCount))
        engine.inputNode.installTap(onBus: 0, bufferSize: 256, format: client, block: pipeline.makeTapBlock(levels: inputMeter.tap))
        tapInstalled = true
        monitorConnected = false
        isInputRunning = true
    }

    func teardownGraph() {
        engine.stop()
        stopInput(failure: .notRunning)
        state = .stopped
    }

    func stopInput(failure: AudioEngineError) {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            if monitorConnected { engine.disconnectNodeOutput(engine.inputNode) }
            tapInstalled = false
            monitorConnected = false
        }
        pipeline.stopInput()
        finishRecording()
        pipeline.failSegments(failure)
        if isInputRunning { isInputRunning = false }
        inputFormat = nil
    }

    func applyMonitoring() {
        monitorMixer.outputVolume = monitorGain
        guard tapInstalled, let inputFormat else { return }
        if monitorAudible, !monitorConnected {
            let format = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate,
                                       channels: AVAudioChannelCount(inputFormat.channelCount))
            engine.connect(engine.inputNode, to: monitorMixer, format: format)
            engine.connect(monitorMixer, to: engine.mainMixerNode, format: nil)
            monitorConnected = true
        } else if !monitorAudible, monitorConnected {
            engine.disconnectNodeOutput(engine.inputNode)
            monitorConnected = false
        }
    }

    public func refreshLatency() {
        guard isInputRunning, state == .running else {
            if monitorLatency != nil { monitorLatency = nil }
            return
        }
        let session = AVAudioSession.sharedInstance()
        let rate = session.sampleRate > 0 ? session.sampleRate : DigitoneAudioModule.preferredSampleRate
        let buffer = Int((session.ioBufferDuration * rate).rounded())
        inputBufferFrames = buffer
        outputBufferFrames = buffer
        monitorLatency = MonitorLatency(
            input: DeviceLatency(sampleRate: rate, deviceFrames: Int((session.inputLatency * rate).rounded()), bufferFrames: buffer),
            handoffFrames: 0,
            output: DeviceLatency(sampleRate: rate, deviceFrames: Int((session.outputLatency * rate).rounded()), bufferFrames: buffer))
    }

    public func diagnostics() -> MonitorDiagnostics {
        var result = MonitorDiagnostics()
        result.overloads = overloadCount
        return result
    }

    func enlargeBuffer(input: Bool) {}

    /// Rebuilds after a route change; keeps recording when the input is unchanged.
    func restart() {
        guard !isRebuilding else { return }
        let previousInput = inputDevice
        teardownGraphKeepingTake(previousInput: previousInput)
        playback.stop()
        isPlaying = false
        do {
            try startGraph()
        } catch {
            state = .stopped
            finishRecording()
            lastError = Self.wrap(error, "перезапуск аудио")
            pipeline.failSegments(lastError ?? AudioEngineError.notRunning)
        }
    }

    private func teardownGraphKeepingTake(previousInput: AudioDevice?) {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            if monitorConnected { engine.disconnectNodeOutput(engine.inputNode) }
            tapInstalled = false
            monitorConnected = false
        }
        pipeline.stopInput()
        isInputRunning = false
        if resolveInput()?.id != previousInput?.id {
            finishRecording()
            pipeline.failSegments(AudioEngineError.deviceMissing(previousInput?.name ?? "аудиовход"))
            pipeline.resetCapture()
        }
    }

    func reroute(input: Bool) throws {
        if state == .running {
            restart()
            if state != .running, let lastError { throw lastError }
        } else {
            inputDevice = resolveInput()
            outputDevice = resolveOutput()
        }
    }

    func engineConfigurationChanged() {
        guard state == .running else { return }
        restart()
    }

    /// iOS reroutes by itself and reports it through a configuration change.
    func devicesChanged() {
        guard !isRebuilding else { return }
        if state != .running {
            inputDevice = resolveInput()
            outputDevice = resolveOutput()
            if autoStartArmed, permission == .granted, wantsAutomaticInput, startTask == nil {
                Task { await autoStart() }
            }
        }
        refreshMonitor()
    }

    fileprivate func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            if inputRequested {
                // USB interfaces take the route automatically; without one, play from the speaker.
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setPreferredSampleRate(DigitoneAudioModule.preferredSampleRate)
            try session.setPreferredIOBufferDuration(Double(options.bufferFrames) / DigitoneAudioModule.preferredSampleRate)
            try session.setActive(true)
        } catch {
            throw Self.wrap(error, "настройка аудиосессии")
        }
        devices.refresh()
        if inputRequested, let id = resolveInput()?.id, let port = AudioDeviceDiscovery.port(forID: id) {
            try? session.setPreferredInput(port)
        }
        if inputRequested {
            let speaker = resolveOutput()?.transport == .builtIn && session.currentRoute.outputs.first?.portType != .usbAudio
            try? session.overrideOutputAudioPort(speaker ? .speaker : .none)
        }
        devices.refresh()
    }

    func handleInterruption(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began:
            guard state == .running else { return }
            playback.stop()
            isPlaying = false
            engine.stop()
            stopInput(failure: .interrupted)
            state = .interrupted
            lastError = .interrupted
        case .ended:
            guard state == .interrupted else { return }
            if shouldResume { restart() } else { state = .stopped }
        default:
            break
        }
    }
}
#endif
