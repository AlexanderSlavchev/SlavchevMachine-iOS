import SwiftUI

struct TourStep {
    let targetId: String?
    let title: String
    let body: String
}

let kTourSteps: [TourStep] = [
    .init(targetId: nil, title: "WELCOME", body: "Interactive tour of the gestures that aren't obvious. Walk through with NEXT — re-open any time from Settings."),
    .init(targetId: "brand", title: "SETTINGS LIVE HERE", body: "Tap the SLAVCHEV MACHINE wordmark to open Settings — accent colour, Bluetooth bindings, and this tour."),
    .init(targetId: "scene_library_icon", title: "SCENE LIBRARY", body: "Save full snapshots (sequencer + samples + mix) as scenes, organise them into setlists for live performance."),
    .init(targetId: "bpm_display", title: "TEMPO", body: "Drag up/down directly on the BPM number to change tempo live — the playhead doesn't drop a beat. Tap to type a precise value. LOCK keeps the tempo when you load a beat preset."),
    .init(targetId: "time_signature", title: "TIME SIGNATURE", body: "Tap the TIME chip to switch the sequencer between 4/4, 3/4, 6/8, 7/8, 11/16 and more. The step count and the beat grouping adapt instantly."),
    .init(targetId: "play_button", title: "PLAY — AND LONG-PRESS", body: "Tap to start/stop. Long-press to bind a Bluetooth page-turner button. Same long-press trick works on Stop, ‹ ›, B, and Fill 1 / 2."),
    .init(targetId: "looper_button", title: "AUDIO LOOPER", body: "Records audio from the mic, a USB-C interface or sound card and loops it locked to the bars. Tap to record, tap to finish, tap to play/stop. Long-press to clear."),
    .init(targetId: "scene_nav", title: "SCENE NAVIGATION", body: "Use the ‹ › arrows to jump between scenes in the current setlist. Tap the label between them to jump straight into the Scene Library."),
    .init(targetId: "sequencer_step", title: "STEP SEQUENCER", body: "Tap a step to toggle on/off. Drag up/down on a step to fine-tune velocity (taller fill = louder)."),
    .init(targetId: "drum_pad", title: "DRUM PADS", body: "Tap to trigger. The vertical position of your finger sets velocity — top = soft, bottom = loud. Long-press to pick a different .wav."),
    .init(targetId: "section_b", title: "A / B VARIATION", body: "Flip the sequencer between A and B sections. B starts as a smart variation of A."),
    .init(targetId: "fill_button", title: "FILLS", body: "Trigger a delicate fill that lands on the next downbeat. Snare-led (Fill 1) and tom-led (Fill 2). A crash punctuates the new bar."),
    .init(targetId: "mode_switcher", title: "PADS / LOOPER / MIX / EQ", body: "Switches the bottom panel between the pad grid, the looper's levels & interactive EQ, per-pad volume faders, and the 8-band master EQ."),
    .init(targetId: nil, title: "YOU'RE READY", body: "Re-open this tour any time from Settings. Have fun."),
]

struct CoachMarkOverlay: View {
    @EnvironmentObject var registry: TourRegistry
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var active: Bool
    @State private var step: Int = 0

    var body: some View {
        let accent = vm.accent.tokens
        let current = kTourSteps[step]
        let target = current.targetId.flatMap { registry.targets[$0] }
        ZStack {
            // Dark scrim with cutout.
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.78).ignoresSafeArea()
                    if let r = target {
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: r.width + 12, height: r.height + 12)
                            .position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .compositingGroup()
            }
            VStack(spacing: 12) {
                if target == nil { Spacer() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.title).font(SMFont.sans(13, weight: .black)).tracking(2).foregroundStyle(accent.hex)
                    Text(current.body).font(SMFont.mono(10)).foregroundStyle(.white.opacity(0.9))
                    HStack {
                        Text("\(step + 1) / \(kTourSteps.count)").font(SMFont.mono(8)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        PillButton(label: "BACK", accent: accent) { if step > 0 { step -= 1 } }.opacity(step > 0 ? 1 : 0.3)
                        PillButton(label: "SKIP", accent: accent) { finish() }
                        PillButton(label: step == kTourSteps.count - 1 ? "DONE" : "NEXT", primary: true, accent: accent) {
                            if step < kTourSteps.count - 1 { step += 1 } else { finish() }
                        }
                    }
                }
                .padding(16)
                .background(Chassis.top)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.dim, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding()
                if target != nil { Spacer() }
            }
        }
    }

    private func finish() {
        OnboardingStore.markSeen()
        active = false
    }
}
