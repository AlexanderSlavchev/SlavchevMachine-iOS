import SwiftUI
import UIKit

/// Context-menu dialog opened when a transport button is long-pressed.
/// Offers LEARN BT KEY / RELEARN / UNBIND / CANCEL.
struct TransportContextMenu: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    let request: TransportMenuRequest

    var body: some View {
        let accent = vm.accent.tokens
        let kc = vm.keyController
        let bound = kc.bindings[request.action]
        DialogShell(title: request.action.displayName, accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                if let bound = bound {
                    Text("Bound to \(kc.keyName(for: bound) ?? "USAGE \(bound)")")
                        .font(SMFont.mono(10))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("No key bound yet.")
                        .font(SMFont.mono(10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text("Long-press any transport button to bind a Bluetooth page-turner key. Foreground only on iOS.")
                    .font(SMFont.mono(9))
                    .foregroundStyle(.white.opacity(0.45))
            }
        } actions: {
            if bound != nil {
                PillButton(label: "UNBIND", danger: true, accent: accent) {
                    kc.unbind(request.action); dismiss()
                }
            }
            PillButton(label: bound != nil ? "RELEARN" : "LEARN", primary: true, accent: accent) {
                vm.startLearning(request.action); dismiss()
            }
            PillButton(label: "CANCEL", accent: accent) { dismiss() }
        }
    }
}

/// Full-screen overlay shown while keyController.learningAction is non-nil.
/// Diagnostic box updates as keys arrive. Cancel button calls cancelLearning().
struct TransportLearnOverlay: View {
    @EnvironmentObject var vm: DrumMachineViewModel

    var body: some View {
        let accent = vm.accent.tokens
        let action = vm.keyController.learningAction
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea().contentShape(Rectangle())
            VStack(spacing: 18) {
                Text("LEARN BT KEY")
                    .font(SMFont.sans(11, weight: .black)).tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                Text(action?.displayName ?? "")
                    .font(SMFont.sans(20, weight: .black)).tracking(1)
                    .foregroundStyle(accent.hex)
                Text("Press a key on your Bluetooth page-turner / external keyboard.")
                    .font(SMFont.mono(10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 20)

                if let last = vm.keyController.lastReceivedKey {
                    Text("DETECTED · \(last.name) · code \(last.code)")
                        .font(SMFont.mono(10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(accent.hex)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("waiting for key…")
                        .font(SMFont.mono(10))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                PillButton(label: "CANCEL", primary: true, accent: accent) {
                    vm.keyController.cancelLearning()
                }
            }
            .padding(28)
            .background(Chassis.top)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.dim, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding()
        }
        .transition(.opacity)
    }
}

/// Invisible responder view that captures hardware key events and forwards them to
/// TransportKeyController. UIKit-backed because SwiftUI on iOS 16 has no first-class
/// press-event API equivalent to UIResponder.pressesBegan.
struct KeyCaptureView: UIViewRepresentable {
    @EnvironmentObject var vm: DrumMachineViewModel

    func makeUIView(context: Context) -> KeyCatcherView {
        let v = KeyCatcherView()
        v.onKey = { [weak vm] code, name in
            DispatchQueue.main.async {
                _ = vm?.keyController.handle(keyCode: code, name: name)
            }
        }
        return v
    }

    func updateUIView(_ uiView: KeyCatcherView, context: Context) {
        DispatchQueue.main.async { uiView.becomeFirstResponder() }
    }
}

final class KeyCatcherView: UIView {
    var onKey: ((Int, String) -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed: Bool = false
        for press in presses {
            guard let key = press.key else { continue }
            let usage = key.keyCode
            let name: String
            switch usage {
            case .keyboardSpacebar: name = "SPACE"
            case .keyboardReturnOrEnter: name = "ENTER"
            case .keypadEnter: name = "NUMPAD ENTER"
            case .keyboardUpArrow: name = "ARROW UP"
            case .keyboardDownArrow: name = "ARROW DOWN"
            case .keyboardLeftArrow: name = "ARROW LEFT"
            case .keyboardRightArrow: name = "ARROW RIGHT"
            case .keyboardPageUp: name = "PAGE UP"
            case .keyboardPageDown: name = "PAGE DOWN"
            case .keyboardEscape: name = "ESC"
            case .keyboardVolumeUp: name = "VOLUME UP"
            case .keyboardVolumeDown: name = "VOLUME DOWN"
            default: name = key.charactersIgnoringModifiers.isEmpty ? "USAGE \(usage.rawValue)" : key.charactersIgnoringModifiers.uppercased()
            }
            onKey?(usage.rawValue, name)
            consumed = true
        }
        if !consumed { super.pressesBegan(presses, with: event) }
    }
}
