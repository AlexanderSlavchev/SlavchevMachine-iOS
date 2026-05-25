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
