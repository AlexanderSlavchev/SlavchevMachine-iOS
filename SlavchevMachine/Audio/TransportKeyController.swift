import Foundation
import SwiftUI
import UIKit

enum TransportAction: String, CaseIterable, Codable {
    case play, stop, nextScene, previousScene, sectionToggle
    case fill1, fill2, tempoStepUp, tempoStepDown
    case looperRecord, looperStop

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
