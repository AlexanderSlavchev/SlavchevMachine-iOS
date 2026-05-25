import SwiftUI
import AVFoundation

/// Settings section for picking audio input + forcing output routing.
/// Live-refreshes when devices are plugged/unplugged.
struct AudioRoutingSection: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var currentInputUID: String?
    @State private var currentOutputName: String = "Speaker"
    @State private var forceSpeaker: Bool = SettingsStore.forceSpeakerOutput
    @State private var monitorInput: Bool = SettingsStore.monitorInput
    @State private var latencyOffset: Double = SettingsStore.latencyOffsetMs

    var body: some View {
        let accent = vm.accent.tokens
        VStack(alignment: .leading, spacing: 8) {
            // OUTPUT
            HStack {
                Text("OUTPUT")
                    .font(SMFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(currentOutputName.uppercased())
                    .font(SMFont.mono(10, weight: .bold))
                    .foregroundStyle(accent.hex)
            }
            HStack {
                Text("FORCE PHONE SPEAKER")
                    .font(SMFont.mono(9))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $forceSpeaker)
                    .labelsHidden()
                    .tint(accent.hex)
                    .onChange(of: forceSpeaker) { v in
                        SettingsStore.forceSpeakerOutput = v
                        vm.audio.applyRoutingPreferences()
                        refresh()
                    }
            }
            Text("ON = always use the built-in speaker, even when a USB / Bluetooth device is connected.")
                .font(SMFont.mono(8))
                .foregroundStyle(.white.opacity(0.4))

            Divider().background(accent.dim).padding(.vertical, 4)

            // INPUT
            HStack {
                Text("INPUT")
                    .font(SMFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text((vm.audio.currentInput()?.portName ?? "—").uppercased())
                    .font(SMFont.mono(10, weight: .bold))
                    .foregroundStyle(accent.hex)
            }
            HStack {
                Text("LIVE MONITOR")
                    .font(SMFont.mono(9))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $monitorInput)
                    .labelsHidden()
                    .tint(accent.hex)
                    .onChange(of: monitorInput) { v in
                        vm.audio.setMonitorEnabled(v)
                    }
            }
            Text("ON = hear the input through the output speakers in real time. Use headphones to avoid feedback. Helpful for confirming the mic is alive.")
                .font(SMFont.mono(8))
                .foregroundStyle(.white.opacity(0.4))

            Divider().background(accent.dim).padding(.vertical, 4)

            // LOOP LATENCY FINE-TUNE
            HStack {
                Text("LOOP TIMING")
                    .font(SMFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(String(format: "%+.0f ms", latencyOffset))
                    .font(SMFont.mono(10, weight: .bold))
                    .foregroundStyle(accent.hex)
            }
            Slider(value: $latencyOffset, in: -250...250, step: 1) {
                Text("Loop timing")
            } onEditingChanged: { editing in
                if !editing {
                    SettingsStore.latencyOffsetMs = latencyOffset
                    vm.audio.recalculateLoopLatency()
                }
            }
            .tint(accent.hex)
            HStack {
                Button("−10") { adjustOffset(-10) }
                    .font(SMFont.mono(9, weight: .bold))
                    .foregroundStyle(accent.hex)
                Button("RESET") { adjustOffset(-latencyOffset) }
                    .font(SMFont.mono(9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                Button("+10") { adjustOffset(+10) }
                    .font(SMFont.mono(9, weight: .bold))
                    .foregroundStyle(accent.hex)
                Spacer()
            }
            Text("Negative = play earlier (loop drags behind beat → move left). Positive = play later. Built-in mic usually needs +5..+15 ms.")
                .font(SMFont.mono(8))
                .foregroundStyle(.white.opacity(0.4))

            if inputs.isEmpty {
                Text("No inputs available. Connect a microphone, USB interface, or grant mic permission.")
                    .font(SMFont.mono(8))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(inputs, id: \.uid) { port in
                        Button {
                            select(port)
                        } label: {
                            HStack {
                                Image(systemName: currentInputUID == port.uid ? "circle.fill" : "circle")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(currentInputUID == port.uid ? accent.hex : .white.opacity(0.35))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(port.portName)
                                        .font(SMFont.mono(10, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(prettyPortType(port.portType))
                                        .font(SMFont.mono(8))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            // Devices plugged/unplugged — refresh on main queue.
            DispatchQueue.main.async { refresh() }
        }
    }

    private func refresh() {
        inputs = vm.audio.availableInputs()
        currentInputUID = vm.audio.currentInput()?.uid
        currentOutputName = vm.audio.currentOutputName()
        forceSpeaker = SettingsStore.forceSpeakerOutput
        latencyOffset = SettingsStore.latencyOffsetMs
    }

    private func adjustOffset(_ delta: Double) {
        latencyOffset = max(-100, min(100, latencyOffset + delta))
        SettingsStore.latencyOffsetMs = latencyOffset
        vm.audio.recalculateLoopLatency()
    }

    private func select(_ port: AVAudioSessionPortDescription) {
        SettingsStore.preferredInputUID = port.uid
        // ONE call. AudioEngine's reconfig handler will re-evaluate route automatically.
        // (Calling both setPreferredInput AND applyPreferredInput would fire two route
        // changes for one user action.)
        try? AVAudioSession.sharedInstance().setPreferredInput(port)
        // Refresh on next runloop tick so the active route catches up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { refresh() }
    }

    private func prettyPortType(_ t: AVAudioSession.Port) -> String {
        switch t {
        case .builtInMic: return "BUILT-IN MICROPHONE"
        case .headsetMic: return "HEADSET MIC"
        case .lineIn: return "LINE IN"
        case .usbAudio: return "USB AUDIO DEVICE"
        case .bluetoothHFP: return "BLUETOOTH MIC"
        case .bluetoothLE: return "BLUETOOTH LE"
        case .airPlay: return "AIRPLAY"
        case .carAudio: return "CAR AUDIO"
        default: return t.rawValue.uppercased()
        }
    }
}
