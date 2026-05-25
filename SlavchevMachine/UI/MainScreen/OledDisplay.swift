import SwiftUI

/// Two-row OLED panel matching the design:
/// - Row 1: big BPM number (32pt mono, -1 letter-spacing) + "BPM" label, recording dot + play/stop status
/// - Row 2: PATTERN id + MODE label, both in mono with LED bleed
struct OledDisplay: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showTimeSig: Bool
    @State private var bpmInputText: String = ""
    @State private var showBpmInput: Bool = false
    @State private var recordPulse: Bool = false

    var body: some View {
        let accent = vm.accent.tokens
        OledPanel(accent: accent) {
            VStack(alignment: .leading, spacing: 4) {
                row1(accent: accent)
                row2(accent: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("BPM", isPresented: $showBpmInput) {
            TextField("\(Int(vm.bpm))", text: $bpmInputText).keyboardType(.decimalPad)
            Button("OK") {
                if let v = Float(bpmInputText) { vm.setBpm(v) }
                bpmInputText = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter tempo (40–240)")
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                recordPulse.toggle()
            }
        }
    }

    private func row1(accent: AccentTokens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: "%.1f", vm.bpm))
                .font(SMFont.mono(32, weight: .bold))
                .tracking(-1)
                .ledBleed(accent)
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            let delta = Float(-g.translation.height) * 0.25
                            let v = vm.bpm + delta
                            vm.setBpm(v)
                        }
                )
                .onTapGesture { showBpmInput = true }
                .tourTarget("bpm_display")

            Text("BPM")
                .font(SMFont.mono(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(accent.hex.opacity(0.7))

            Spacer()

            if vm.recording {
                Circle()
                    .fill(Chassis.recRed)
                    .frame(width: 7, height: 7)
                    .shadow(color: Chassis.recRed, radius: 4)
                    .opacity(recordPulse ? 1 : 0.3)
            }
            Text(vm.isPlaying ? "▶ PLAY" : "■ STOP")
                .font(SMFont.mono(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(accent.hex.opacity(0.8))
        }
    }

    private func row2(accent: AccentTokens) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("PATTERN")
                    .font(SMFont.mono(9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(accent.hex.opacity(0.5))
                Text(vm.sceneName)
                    .font(SMFont.mono(13, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(accent.hex.opacity(0.95))
            }
            Spacer()
            Button { showTimeSig = true } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("TIME")
                        .font(SMFont.mono(9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(accent.hex.opacity(0.5))
                    Text(vm.timeSignature.format())
                        .font(SMFont.mono(13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(accent.hex.opacity(0.95))
                }
            }
            .buttonStyle(.plain)
            .tourTarget("time_signature")

            Spacer().frame(width: 10)

            Button { vm.tempoLock.toggle() } label: {
                Image(systemName: vm.tempoLock ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.tempoLock ? accent.hex : accent.hex.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Combined OLED + transport row at the bottom of the screen.
struct OledAndTransportRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showTimeSig: Bool
    @Binding var showBeatLibrary: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OledDisplay(showTimeSig: $showTimeSig)
                .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                // Top row — three equal-sized circular buttons: LOOP · REC · STOP
                HStack(spacing: 8) {
                    LooperButton(size: 38)
                    TransportButton(kind: .rec,
                                    active: vm.recording,
                                    size: 38,
                                    icon: "circle.fill",
                                    action: { vm.toggleRecording() })
                    TransportButton(kind: .stop,
                                    active: !vm.isPlaying,
                                    size: 38,
                                    icon: "square.fill",
                                    action: { vm.stop() },
                                    onLongPress: { vm.openTransportMenu(for: .stop) })
                }
                // Bottom — PLAY centered, slightly larger.
                TransportButton(kind: .play,
                                active: vm.isPlaying,
                                size: 50,
                                icon: vm.isPlaying ? "pause.fill" : "play.fill",
                                action: { vm.togglePlay() },
                                onLongPress: { vm.openTransportMenu(for: .play) })
                .tourTarget("play_button")
            }
        }
    }
}
