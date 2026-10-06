import Foundation

public enum AudioEngineError: Error, LocalizedError, Equatable {
    case permissionDenied
    case permissionConfigurationMissing
    case noInputDevice
    case noOutputDevice
    case deviceMissing(String)
    case formatUnsupported(String)
    case system(String, Int32)
    case notRunning
    case alreadyRecording
    case fileRead(String)
    case fileWrite(String)
    case interrupted
    case inputOverflow
    case captureOverflow
    case operationInProgress
    case fileExists(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            #if os(iOS)
            return "Нет доступа к аудиовходу. Разреши микрофон в Настройках → Digitone Studio."
            #else
            return "Нет доступа к микрофону. Разреши его в Системных настройках → Конфиденциальность → Микрофон."
            #endif
        case .permissionConfigurationMissing:
            return "В этой сборке не задано описание доступа к микрофону. Запусти приложение из установленной сборки."
        case .noInputDevice:
            return "Нет аудиовхода. Подключи Digitone по USB в режиме USB AUDIO/MIDI."
        case .noOutputDevice:
            return "Нет аудиовыхода. Проверь подключение устройства."
        case .deviceMissing(let name):
            return "Аудиоустройство «\(name)» не найдено. Проверь кабель и режим USB."
        case .formatUnsupported(let detail):
            return "Формат аудио не поддерживается: \(detail)."
        case .system(let operation, let status):
            return "Ошибка аудиосистемы: \(operation) (\(status))."
        case .notRunning:
            return "Аудиодвижок не запущен."
        case .alreadyRecording:
            return "Запись уже идёт."
        case .fileRead(let name):
            return "Не удалось прочитать аудиофайл «\(name)»."
        case .fileWrite(let name):
            return "Не удалось записать аудиофайл «\(name)»."
        case .interrupted:
            return "Звук прерван системой (звонок или другое приложение)."
        case .inputOverflow:
            return "Аудиовход поступал быстрее, чем запись успевала сохраняться. Запись остановлена; сохранённая часть остаётся на диске."
        case .captureOverflow:
            return "Часть входного аудио потеряна. Захват сэмпла остановлен; попробуй ещё раз."
        case .operationInProgress:
            return "Аудиодвижок уже запускается."
        case .fileExists(let name):
            return "Файл «\(name)» уже существует. Выбери новое имя записи."
        }
    }
}
