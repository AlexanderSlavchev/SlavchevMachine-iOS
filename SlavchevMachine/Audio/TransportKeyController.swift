import Foundation
import SwiftUI
import UIKit

enum TransportAction: String, CaseIterable, Codable {
    case play, stop, nextScene, previousScene, sectionToggle
    case fill1, fill2, tempoStepUp, tempoStepDown
    case looperRecord, looperStop
    case looperMute1, looperMute2, looperMute3, looperMute4

    var displayName: String {
        switch self {
        case .play: return "PLAY"
        case .stop: return "STOP"
        case .nextScene: return "NEXT SCENE"
        case .previousScene: return "PREVIOUS SCENE"
        case .sectionToggle: return "SECTION A/B"
        case .fill1: return "FILL 1"
        case .fill2: return "FILL 2"
        case .tempoStepUp: return "TEMPO +"
        case .tempoStepDown: return "TEMPO −"
        case .looperRecord: return "LOOPER REC"
        case .looperStop: return "LOOPER STOP"
        case .looperMute1: return "MUTE IN 1"
        case .looperMute2: return "MUTE IN 2"
        case .looperMute3: return "MUTE IN 3"
        case .looperMute4: return "MUTE IN 4"
        }
    }

    /// Looper-mute actions, indexed by track (0-based). nil for non-mute actions.
    var looperMuteTrack: Int? {
        switch self {
        case .looperMute1: return 0
        case .looperMute2: return 1
        case .looperMute3: return 2
        case .looperMute4: return 3
        default: return nil
        }
    }

    /// The mute action for a given track index (0-based), if any.
    static func looperMute(track: Int) -> TransportAction? {
        switch track {
        case 0: return .looperMute1
        case 1: return .looperMute2
        case 2: return .looperMute3
        case 3: return .looperMute4
        default: return nil
        }
    }
}

/// Key represented as an iOS UIKeyboardHIDUsage rawValue (Int) for forward-compat; -1 means unbound.
@MainActor
final class TransportKeyController: ObservableObject {
    @Published var bindings: [TransportAction: Int] = [:]
    @Published var learningAction: TransportAction?
    @Published var lastReceivedKey: (code: Int, name: String)?

    var onAction: (TransportAction) -> Void = { _ in }

    private let prefsKey = "transport_keys"

    init() { load() }

    func load() {
        let defaults = UserDefaults.standard
        guard let dict = defaults.dictionary(forKey: prefsKey) as? [String: Int] else { return }
        for (k, v) in dict {
            if let a = TransportAction(rawValue: k) { bindings[a] = v }
        }
    }

    func save() {
        var dict: [String: Int] = [:]
        for (k, v) in bindings { dict[k.rawValue] = v }
        UserDefaults.standard.set(dict, forKey: prefsKey)
    }

    func startLearning(_ action: TransportAction) { learningAction = action }
    func cancelLearning() { learningAction = nil }
    func unbind(_ action: TransportAction) { bindings.removeValue(forKey: action); save() }
    func resetAll() { bindings.removeAll(); save() }

    /// Called from a view's `pressesBegan`. Returns true if handled (e.g. learning capture).
    @discardableResult
    func handle(keyCode raw: Int, name: String) -> Bool {
        lastReceivedKey = (raw, name)
        if let action = learningAction {
            // Remove any existing binding to this key.
            for (k, v) in bindings where v == raw { bindings.removeValue(forKey: k) }
            bindings[action] = raw
            learningAction = nil
            save()
            return true
        }
        // Fire bound action if any.
        for (a, v) in bindings where v == raw {
            onAction(a)
            return true
        }
        return false
    }

    func keyName(for code: Int) -> String? {
        guard let hid = UIKeyboardHIDUsage(rawValue: code) else { return "0x\(String(code, radix: 16))" }
        return KeyName.friendly(hid)
    }
}

enum KeyName {
    static func friendly(_ usage: UIKeyboardHIDUsage) -> String {
        switch usage {
        case .keyboardVolumeUp: return "VOLUME UP"
        case .keyboardVolumeDown: return "VOLUME DOWN"
        case .keyboardPageUp: return "PAGE UP"
        case .keyboardPageDown: return "PAGE DOWN"
        case .keyboardUpArrow: return "ARROW UP"
        case .keyboardDownArrow: return "ARROW DOWN"
        case .keyboardLeftArrow: return "ARROW LEFT"
        case .keyboardRightArrow: return "ARROW RIGHT"
        case .keyboardReturnOrEnter: return "ENTER"
        case .keypadEnter: return "NUMPAD ENTER"
        case .keyboardSpacebar: return "SPACE"
        case .keyboardEscape: return "ESC"
        default:
            return "USAGE \(usage.rawValue)"
        }
    }
}
