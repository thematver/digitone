import DigitoneAudio

extension WorkspaceModel {
    /// Opening a studio window arms hot-plug monitoring only for the Digitone.
    /// Preview workspaces have no audio graph and never ask for permission.
    func startMonitoringIfNeeded() async {
        await audio?.autoStart()
    }

    func toggleMonitor() async {
        guard let audio else { return }
        audio.isMonitoringInput.toggle()
        if audio.isMonitoringInput {
            await audio.autoStart()
        }
    }

    func selectAudioInput(_ device: AudioDevice?) async {
        guard let audio else { return }
        do {
            try audio.selectInput(device)
            if audio.isMonitoringInput { await audio.autoStart() }
        } catch { self.error = error.localizedDescription }
    }

    func selectAudioOutput(_ device: AudioDevice?) {
        do { try audio?.selectOutput(device) }
        catch { self.error = error.localizedDescription }
    }
}
