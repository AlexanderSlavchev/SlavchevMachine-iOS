import SwiftUI

/// Header row above sequencer: "STEP · {SELECTED PAD LABEL}" on the left,
/// HUMANIZE toggle + "SECTION A/B" on the right (humanize sits left of section).
struct SequencerHeader: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    var body: some View {
        let accent = vm.accent.tokens
        let padName = vm.selectedPad < KitStore.padLabels.count ? KitStore.padLabels[vm.selectedPad] : "PAD"
        HStack(spacing: 10) {
            Text("STEP · \(padName)")
                .font(SMFont.mono(9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
            HumanizeToggle()
            Text(vm.activeSection == .a ? "SECTION A" : "SECTION B")
                .font(SMFont.mono(9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(accent.hex)
        }
        .frame(height: 18)
    }
}

struct HumanizeToggle: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    var body: some View {
        let accent = vm.accent.tokens
        Button { vm.humanize.toggle() } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(vm.humanize ? accent.hex : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                Text("HUMANIZE")
                    .font(SMFont.mono(8, weight: .bold))
                    .tracking(1.5)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(vm.humanize ? accent.hex : Color.white.opacity(0.55))
            .background(vm.humanize ? accent.dim : Color.clear)
            .overlay(
                Capsule().stroke(vm.humanize ? accent.hex : Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 16-step (or N-step) sequencer row.
/// Tap = toggle on/off. Drag ↕ = adjust velocity (up = louder, down = quieter / off).
/// Live preview while dragging.
struct SequencerRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @State private var dragVelocity: [Int: Int] = [:]       // live preview during drag
    @State private var dragStartVelocity: [Int: Int] = [:]  // captured at gesture start

    private static let dragThreshold: CGFloat = 6
    private static let velocityPerPoint: Double = 1.5       // sensitivity (1pt drag = ~1.5 vel)

    var body: some View {
        let accent = vm.accent.tokens
        let focusedPad = vm.selectedPad
        let activeMatrix = vm.activeSection == .a ? vm.matrixA : vm.matrixB
        let stepRow = activeMatrix[focusedPad]
        let total = vm.timeSignature.stepCount

        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { step in
                    let committed = stepRow[step]
                    let preview = dragVelocity[step]
                    let displayedVel = preview ?? committed
                    let current = step == vm.currentStep
                    let beatStart = step % 4 == 0
                    SequencerStep(
                        velocity: displayedVel,
                        current: current,
                        beatStart: beatStart,
                        index: step,
                        accent: accent
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                if dragStartVelocity[step] == nil {
                                    dragStartVelocity[step] = committed
                                }
                                if abs(g.translation.height) > Self.dragThreshold {
                                    let initial = dragStartVelocity[step] ?? 0
                                    // Drag UP = positive (translation.height is negative when going up)
                                    let delta = Int((-g.translation.height) * Self.velocityPerPoint)
                                    let target = max(0, min(127, initial + delta))
                                    dragVelocity[step] = target
                                }
                            }
                            .onEnded { g in
                                defer {
                                    dragVelocity[step] = nil
                                    dragStartVelocity[step] = nil
                                }
                                if abs(g.translation.height) > Self.dragThreshold,
                                   let dv = dragVelocity[step] {
                                    vm.setStepVelocity(pad: focusedPad, step: step, velocity: dv)
                                } else {
                                    // Pure tap → toggle on/off.
                                    vm.toggleStep(pad: focusedPad, step: step)
                                }
                            }
                    )
                    .tourTarget(step == 0 ? "sequencer_step" : nil)

                    // 4pt gutter between groups of 4
                    if (step % 4 == 3) && (step < total - 1) {
                        Color.clear.frame(width: 4)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 56)
    }
}

/// One sequencer cell. Background fades to "active" gradient once velocity > 0.
/// The accent fill grows from the bottom proportionally to velocity (taller = louder).
private struct SequencerStep: View {
    let velocity: Int
    let current: Bool
    let beatStart: Bool
    let index: Int
    let accent: AccentTokens

    var body: some View {
        let active = velocity > 0
        let restFill = beatStart ? Color.white.opacity(0.08) : Color.white.opacity(0.04)
        let velocityFraction = max(0.10, Double(velocity) / 127.0)
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Rest layer (always present)
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [restFill, Color.white.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))

                // Velocity fill — height proportional to velocity, grows from bottom.
                if active {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [accent.hex, accent.hex.opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: max(4, geo.size.height * velocityFraction))
                }

                // Outline
                if current {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(accent.bright, lineWidth: 1.5)
                        .shadow(color: accent.soft, radius: 8)
                        .shadow(color: accent.dim, radius: 16)
                } else if active {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.04), .clear],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                }

                Text("\(index + 1)")
                    .font(SMFont.mono(8, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(active ? Color.black.opacity(0.55) : Color.white.opacity(0.3))
                    .padding(.bottom, 3)
            }
        }
    }
}
