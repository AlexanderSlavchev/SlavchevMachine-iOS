import SwiftUI
import AVFoundation

/// Looper Routing menu — pick which input channels the looper records. Each selected channel
/// becomes its own looper track (played together, mutable individually). Only useful with a
/// multi-channel input (USB interface); built-in mic = 1 channel.
struct LooperRoutingDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selected: [Int] = SettingsStore.looperRoutingChannels
    @State private var channelCount: Int = 1
    @State private var names: [String] = []

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "LOOPER ROUTING", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose which input channels the looper records. Each selected channel becomes a separate track you can mute on its own (max \(Looper.maxTracks)).")
                    .font(SMFont.mono(9))
                    .foregroundStyle(.white.opacity(0.6))

                if channelCount <= 1 {
                    Text("The current input has only one channel. Connect a multi-channel audio interface to route several inputs.")
                        .font(SMFont.mono(9))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(0..<channelCount, id: \.self) { ch in
                        channelRow(ch, accent: accent)
                    }
                    Text("\(selected.count) of \(min(channelCount, Looper.maxTracks)) selected")
                        .font(SMFont.mono(8))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        } actions: {
            PillButton(label: "DONE", primary: true, accent: accent) { dismiss() }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            DispatchQueue.main.async { refresh() }
        }
    }

    @ViewBuilder
    private func channelRow(_ ch: Int, accent: AccentTokens) -> some View {
        let isOn = selected.contains(ch)
        let trackIdx = selected.firstIndex(of: ch)
        let full = !isOn && selected.count >= Looper.maxTracks
        Button {
            toggle(ch)
        } label: {
            HStack {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isOn ? accent.hex : .white.opacity(0.35))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ch < names.count ? names[ch] : "INPUT \(ch + 1)")
                        .font(SMFont.mono(10, weight: .semibold))
                        .foregroundStyle(.white)
                    if isOn, let t = trackIdx {
                        Text("TRACK \(t + 1)")
                            .font(SMFont.mono(8))
                            .foregroundStyle(accent.hex)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.4 : 1)
    }

    private func toggle(_ ch: Int) {
        if let i = selected.firstIndex(of: ch) {
            selected.remove(at: i)
        } else {
            guard selected.count < Looper.maxTracks else { return }
            selected.append(ch)
        }
        if selected.isEmpty { selected = [0] }   // never record nothing
        selected.sort()
        SettingsStore.looperRoutingChannels = selected
        vm.applyLooperRouting()
    }

    private func refresh() {
        channelCount = vm.audio.availableInputChannelCount()
        names = vm.audio.inputChannelNames()
        // Drop selections beyond what the current device offers.
        let avail = selected.filter { $0 < channelCount }
        selected = avail.isEmpty ? [0] : avail
    }
}
