import Foundation

enum AccentChoice: String, CaseIterable, Codable {
    case cyan = "Cyan"
    case green = "Green"
    case fuchsia = "Fuchsia"
}

enum SettingsStore {
    private static let kAccent = "sm.accent"
    private static let kStepUp = "sm.tempo_step_up"
    private static let kStepDown = "sm.tempo_step_down"
    private static let kForceSpeaker = "sm.force_speaker_output"
    private static let kPreferredInput = "sm.preferred_input_uid"

    static var accent: AccentChoice {
        get { AccentChoice(rawValue: UserDefaults.standard.string(forKey: kAccent) ?? "") ?? .cyan }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kAccent) }
    }

    static var tempoStepUp: Int {
        get { UserDefaults.standard.object(forKey: kStepUp) as? Int ?? 5 }
        set { UserDefaults.standard.set(max(1, min(50, newValue)), forKey: kStepUp) }
    }

    static var tempoStepDown: Int {
        get { UserDefaults.standard.object(forKey: kStepDown) as? Int ?? 5 }
        set { UserDefaults.standard.set(max(1, min(50, newValue)), forKey: kStepDown) }
    }

    /// When ON, audio always plays through the built-in phone speaker, ignoring external
    /// devices (USB sound card, Bluetooth A2DP, headphones). Useful when you want monitor
    /// audio on the phone while a USB recorder is plugged in but listening elsewhere.
    static var forceSpeakerOutput: Bool {
        get { UserDefaults.standard.bool(forKey: kForceSpeaker) }
        set { UserDefaults.standard.set(newValue, forKey: kForceSpeaker) }
    }

    /// Persisted UID of the preferred input port (matches AVAudioSessionPortDescription.uid).
    /// If nil or unavailable at startup, iOS picks the default (usually built-in mic).
    static var preferredInputUID: String? {
        get { UserDefaults.standard.string(forKey: kPreferredInput) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: kPreferredInput) }
            else { UserDefaults.standard.removeObject(forKey: kPreferredInput) }
        }
    }

    private static let kMonitor = "sm.monitor_input"
    /// Live mic-through-speaker monitoring. Lets the user hear what's being recorded.
    /// Default OFF (causes feedback when output goes to built-in speaker with no headphones).
    static var monitorInput: Bool {
        get { UserDefaults.standard.bool(forKey: kMonitor) }
        set { UserDefaults.standard.set(newValue, forKey: kMonitor) }
    }

    private static let kLatencyOffset = "sm.latency_offset_ms"
    /// User-tunable fine-tune for loop latency compensation (in milliseconds).
    /// Default 0. Positive pulls the loop EARLIER (more compensation — for when loop drags
    /// behind the beat). Negative pushes later. Range: -250..+250 ms.
    static var latencyOffsetMs: Double {
        get { UserDefaults.standard.object(forKey: kLatencyOffset) as? Double ?? 0 }
        set { UserDefaults.standard.set(max(-250, min(250, newValue)), forKey: kLatencyOffset) }
    }

    private static let kLooperRouting = "sm.looper_routing_channels"
    /// Hardware channel indices (0-based) recorded into looper tracks, in track order
    /// (track 0..n-1). Default [0] = the original single-channel behavior. Capped at maxTracks.
    static var looperRoutingChannels: [Int] {
        get { (UserDefaults.standard.array(forKey: kLooperRouting) as? [Int]) ?? [0] }
        set {
            let cleaned = newValue.isEmpty ? [0] : Array(newValue.prefix(Looper.maxTracks))
            UserDefaults.standard.set(cleaned, forKey: kLooperRouting)
        }
    }
}

enum OnboardingStore {
    private static let kSeen = "sm.onboarding_seen"

    static var hasSeen: Bool {
        get { UserDefaults.standard.bool(forKey: kSeen) }
        set { UserDefaults.standard.set(newValue, forKey: kSeen) }
    }

    static func markSeen() { hasSeen = true }
    static func reset() { hasSeen = false }
}
