import SwiftUI

struct PadMixPane: View {
    @EnvironmentObject var vm: DrumMachineViewModel

    var body: some View {
        let accent = vm.accent.tokens
        VStack(spacing: 8) {
            HStack {
                Text("PAD MIX · 16 CH")
                    .font(SMFont.sans(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(accent.hex)
                Spacer()
                Button("RESET") {
                    for i in 0..<AudioConstants.numPads { vm.setPadVolume(i, volume: 1) }
                }
                .font(SMFont.mono(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(accent.hex)
            }
            VStack(spacing: 6) {
                ForEach(0..<4) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<4) { col in
                            let pad = row * 4 + col
                            PadFader(padIndex: pad)
                        }
                    }
                }
            }
        }
    }
}

struct PadFader: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let padIndex: Int

    var body: some View {
        let accent = vm.accent.tokens
        let label = padIndex < KitStore.padLabels.count ? KitStore.padLabels[padIndex] : "PAD \(padIndex)"
        let v = vm.padVolumes[padIndex]
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 8).fill(accent.dim)
                    .frame(height: max(2, geo.size.height * CGFloat(v)))
                VStack {
                    Text(label)
                        .font(SMFont.mono(8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 4)
                    Spacer()
                    Text("\(Int(v * 100))%")
                        .font(SMFont.mono(8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { g in
                        let h = geo.size.height
                        let newV = Float(1 - max(0, min(h, g.location.y)) / h)
                        vm.setPadVolume(padIndex, volume: newV)
                    }
            )
            .onTapGesture(count: 2) { vm.setPadVolume(padIndex, volume: 1) }
        }
        .frame(maxWidth: .infinity)
    }
}
