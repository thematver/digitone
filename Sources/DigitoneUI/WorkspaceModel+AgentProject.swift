import Foundation
import DigitoneAgent
import DigitoneCore

extension WorkspaceModel {
    /// Agent projects are local documents. Opening one never sends MIDI.
    func importAgentProject(_ url: URL, studio: StudioModel) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= AgentProject.maximumFileSize else { throw WorkspaceError.fileTooLarge }
            let project = try AgentProject.read(Data(contentsOf: url, options: .mappedIfSafe))
            try Self.validateSequence(project.sequence)
            if !project.sounds.isEmpty {
                guard studio.storageAvailable, !studio.busy else {
                    throw AgentError(studio.busy ? "Дождись завершения операции с прибором и открой проект ещё раз." : "Библиотека недоступна. Проект не открыт, чтобы сохранить его звуки.")
                }
                studio.error = nil
                studio.importSnapshots(try SnapshotArchive.encode(project.sounds.map(\.snapshot)))
                guard studio.error == nil else { return }
            }
            importedAgentSounds = project.sounds
            agentSoundBaseline = ControlModel.attached(to: studio).values
            replaceSequence(project.sequence)
            error = nil
            notice = "«\(project.name)»: \(project.sequence.noteCount) нот, \(project.sounds.count) звуков в библиотеке."
        } catch { self.error = error.localizedDescription }
    }

    func exportAgentProject(studio: StudioModel) -> Data? {
        do {
            let control = ControlModel.attached(to: studio)
            var sounds = importedAgentSounds
            let editedSounds = (0..<ControlModel.trackCount).compactMap { track -> AgentSoundDraft? in
                guard let machine = SynthMachine(rawValue: control.machines[track].rawValue),
                      let channel = control.channelMap.channel(forTrack: track) else { return nil }
                let supportedIDs = Set(HardwareCatalog.parameters(for: control.machines[track]).map(\.id))
                if let baseline = agentSoundBaseline,
                   !control.values.contains(where: { $0.key.scope == .track(track) && supportedIDs.contains($0.key.id) && baseline[$0.key] != $0.value }) {
                    return nil
                }
                let parameters = control.values.reduce(into: [String: Int]()) { result, item in
                    guard item.key.scope == .track(track), supportedIDs.contains(item.key.id) else { return }
                    result[item.key.id] = item.value.value >> 7
                }
                guard !parameters.isEmpty else { return nil }
                guard !sounds.contains(where: { $0.track == track && $0.midiChannel == channel && $0.machine == machine && $0.parameters == parameters }) else { return nil }
                return AgentSoundDraft(name: "Трек \(track + 1) · \(machine.title)", track: track,
                                       midiChannel: channel, machine: machine, parameters: parameters)
            }
            sounds += editedSounds
            return try AgentProject(name: sequence.name, sequence: sequence, sounds: sounds).data()
        } catch { self.error = error.localizedDescription; return nil }
    }
}
