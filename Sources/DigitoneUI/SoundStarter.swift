import DigitoneCore

/// Small, intentionally partial recipes. These are musical starting points, not factory presets
/// or values read from the device; filtering and the rest of the current sound remain as they were.
struct SoundStarter: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let machine: DNMachine
    let coarseValues: [String: Int]

    var parameters: [DNParameter: Int] {
        Dictionary(uniqueKeysWithValues: HardwareCatalog.parameters(for: machine).compactMap { parameter in
            coarseValues[parameter.id].map { (parameter, $0 << 7) }
        })
    }

    static let all: [SoundStarter] = [
        SoundStarter(id: "fm-pluck", title: "FM · щипок", detail: "Короткая атака, затухающий тембр", machine: .fmTone,
                     coarseValues: ["fmTone.syn1.algo": 0, "fmTone.syn1.feedback": 14, "fmTone.syn1.detune": 0,
                                    "fmTone.syn1.mix": 64, "fmTone.syn2.atkA": 0, "fmTone.syn2.decA": 34,
                                    "fmTone.syn2.endA": 0, "fmTone.syn2.levA": 55,
                                    "fmTone.syn2.atkB": 0, "fmTone.syn2.decB": 25,
                                    "fmTone.syn2.endB": 0, "fmTone.syn2.levB": 30,
                                    "amp.mode": 1, "amp.atk": 0, "amp.dec": 48, "amp.sus": 0,
                                    "amp.rel": 22, "amp.vol": 95, "amp.pan": 64]),
        SoundStarter(id: "fm-pad", title: "FM · мягкий пэд", detail: "Плавный вход и длинный хвост", machine: .fmTone,
                     coarseValues: ["fmTone.syn1.algo": 0, "fmTone.syn1.feedback": 8, "fmTone.syn1.detune": 18,
                                    "fmTone.syn1.mix": 64, "fmTone.syn2.atkA": 40, "fmTone.syn2.decA": 80,
                                    "fmTone.syn2.endA": 36, "fmTone.syn2.levA": 48,
                                    "fmTone.syn2.atkB": 48, "fmTone.syn2.decB": 85,
                                    "fmTone.syn2.endB": 30, "fmTone.syn2.levB": 36,
                                    "amp.mode": 1, "amp.atk": 48, "amp.dec": 78, "amp.sus": 96,
                                    "amp.rel": 80, "amp.vol": 85, "amp.pan": 64]),
        SoundStarter(id: "fm-drum", title: "FM · удар", detail: "Спад высоты и короткое тело", machine: .fmDrum,
                     coarseValues: ["fmDrum.syn1.tune": 40, "fmDrum.syn1.sweepTime": 18,
                                    "fmDrum.syn1.sweepDepth": 36, "fmDrum.syn1.algo": 0,
                                    "fmDrum.syn1.feedback": 8, "fmDrum.syn1.fold": 0,
                                    "fmDrum.syn3.hold": 0, "fmDrum.syn3.decay": 35,
                                    "fmDrum.syn3.level": 100, "fmDrum.syn4.noiseLevel": 0,
                                    "amp.mode": 1, "amp.atk": 0, "amp.dec": 40, "amp.sus": 0,
                                    "amp.rel": 10, "amp.vol": 95, "amp.pan": 64])
    ]
}

extension ControlModel {
    func stageSound(_ starter: SoundStarter) {
        guard canEdit(page) else { return }
        stage([:]) // Cancel queued live edits before changing the local page/machine selection.
        setMachine(starter.machine, track: selectedTrack)
        select(page: .syn1)
        stage(starter.parameters)
    }
}

extension DNPage {
    var editorTitle: String {
        switch self {
        case .syn1, .syn2, .syn3, .syn4: "Синтез · \(subpage ?? 1)"
        case .fltr1, .fltr2: "Фильтр · \(subpage ?? 1)"
        case .amp: "Амплитуда"
        case .fx: "Эффекты трека"
        case .mod1, .mod2, .mod3: "LFO · \(subpage ?? 1)"
        case .trig: "Ноты и триггеры"
        case .track: "Уровень трека"
        case .sequencer: "Евклидов ритм"
        case .delay: "Дилей"
        case .reverb: "Реверберация"
        case .chorus: "Хорус"
        case .compressor: "Компрессор"
        case .mixer: "Микшер"
        case .mixerRight: "Правый вход"
        }
    }

    var editorGroupTitle: String {
        switch group {
        case "SYN": "Синтез"
        case "FLTR": "Фильтр"
        case "AMP": "Амплитуда"
        case "FX": "Эффекты"
        case "MOD": "LFO"
        case "TRIG": "Ноты"
        case "TRACK": "Трек"
        case "EUCLID": "Ритм"
        default: editorTitle
        }
    }
}

extension DNParameter {
    var editorTitle: String {
        switch name {
        case "Algorithm": "Алгоритм"
        case "Frequency": "Частота"
        case "Attack Time": "Атака"
        case "Decay Time": "Спад"
        case "Sustain Level": "Уровень удержания"
        case "Release Time": "Отпускание"
        case "Env. Depth": "Глубина огибающей"
        case "Env. Reset": "Сброс огибающей"
        case "Envelope Mode": "Тип огибающей"
        case "Feedback": "Обратная связь"
        case "Detune": "Расстройка"
        case "Harmonics": "Гармоники"
        case "Volume": "Громкость"
        case "Pan": "Панорама"
        case "Track Level": "Уровень трека"
        case "Delay Send": "Посыл в дилей"
        case "Reverb Send": "Посыл в ревербератор"
        case "Chorus Send": "Посыл в хорус"
        case "Speed": "Скорость"
        case "Depth": "Глубина"
        case "Destination": "Назначение"
        case "Waveform": "Форма волны"
        case "Trig Mode": "Режим запуска"
        case "Tune": "Высота"
        case "Mute": "Выключение трека"
        default: name
        }
    }
}
