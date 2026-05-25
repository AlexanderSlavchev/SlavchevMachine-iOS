import SwiftUI

/// Circular looper button matching the design's transport-button style.
/// State / label / colour mapping mirrors Android (spec §11).
///   Tap → advance state (REC cycle / play / stop / cue)
///   Long-press → clear loop
struct LooperButton: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    var size: CGFloat = 38
    @State private var pulse: Bool = false
    @State private var pressed: Bool = false

    var body: some View {
        let accent = vm.accent.tokens
        let state = vm.looperState
        let (label, color, pulsing) = looksFor(state, accent: accent)

        Button { vm.looperTap() } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x20242B), Color(hex: 0x141619)],
                        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)
                    ))
                Circle()
                    .strokeBorder(color, lineWidth: thickBorder(state) ? 2 : 1)
                    .shadow(color: color.opacity(state == .empty || state == .stopped ? 0 : 0.6), radius: 10)
                Text(label)
                    .font(SMFont.mono(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(pulsing && pulse ? 0.45 : 1)
            .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .tourTarget("looper_button")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in vm.looperClear() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .onAppear {
            withAnimation(.linear(duration: 0.28).repeatForever(autoreverses: true)) { pulse.toggle() }
        }
    }

    private func looksFor(_ s: LooperState, accent: AccentTokens) -> (String, Color, Bool) {
        switch s {
        case .empty:      return ("LOOP", Color.white.opacity(0.5), false)
        case .armed:      return ("ARM",  accent.hex, true)
        case .recording:  return ("REC",  Chassis.recRed, false)
        case .endArmed:   return ("END",  Chassis.recRed, true)
        case .playing:    return ("LOOP", accent.hex, false)
        case .stopped:    return ("STOP", Color.white.opacity(0.5), false)
        case .playArmed:  return ("CUE",  accent.hex, true)
        }
    }

    private func thickBorder(_ s: LooperState) -> Bool {
        switch s { case .recording, .endArmed, .playing: return true; default: return false }
    }
}
