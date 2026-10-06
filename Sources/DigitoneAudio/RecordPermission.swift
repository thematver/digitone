import AVFoundation

/// Microphone / audio input authorization.
public enum RecordPermission: Sendable, Equatable {
    case undetermined, denied, granted

    public static var current: RecordPermission {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
        #else
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .undetermined: .undetermined
        default: .denied
        }
        #endif
    }

    /// Shows the system prompt when undetermined; otherwise returns the current status.
    public static func request() async -> RecordPermission {
        guard current == .undetermined else { return current }
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
              !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .denied }
        #if os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        #else
        return await AVAudioApplication.requestRecordPermission() ? .granted : .denied
        #endif
    }
}
