import Foundation

/// The user's "listen to the Digitone" choice and level, kept across launches.
/// Monitoring is on unless the user turned it off.
public struct MonitorSettings {
    public static let enabledKey = "audio.monitor.enabled"
    public static let gainKey = "audio.monitor.gain"
    public static let defaultGain: Float = 0.8

    private let defaults: UserDefaults?
    private var memory: (enabled: Bool, gain: Float)

    /// `defaults == nil` keeps the values in memory only (tools, previews).
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let enabled = defaults?.object(forKey: Self.enabledKey) as? Bool ?? true
        let stored = (defaults?.object(forKey: Self.gainKey) as? NSNumber)?.floatValue
        memory = (enabled, Self.clamp(stored ?? Self.defaultGain))
    }

    public static func inMemory(enabled: Bool = true, gain: Float = defaultGain) -> MonitorSettings {
        var settings = MonitorSettings(defaults: nil)
        settings.memory = (enabled, clamp(gain))
        return settings
    }

    public var isEnabled: Bool {
        get { memory.enabled }
        set { memory.enabled = newValue; defaults?.set(newValue, forKey: Self.enabledKey) }
    }

    /// 0...1, applied before the master level.
    public var gain: Float {
        get { memory.gain }
        set { memory.gain = Self.clamp(newValue); defaults?.set(memory.gain, forKey: Self.gainKey) }
    }

    static func clamp(_ value: Float) -> Float { value.isFinite ? min(max(value, 0), 1) : defaultGain }
}
