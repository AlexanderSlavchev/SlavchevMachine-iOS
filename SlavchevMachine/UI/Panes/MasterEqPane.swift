import SwiftUI

struct MasterEqPane: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showCompressor: Bool

    var body: some View {
        let accent = vm.accent.tokens
        VStack(spacing: 8) {
            HStack {
                Text("MASTER EQ · 8 BAND")
                    .font(SMFont.sans(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(accent.hex)
                Spacer()
                Button("FLAT") { vm.flattenEq() }
                    .font(SMFont.mono(9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(accent.hex)
            }
            HStack(spacing: 4) {
                ForEach(0..<MasterEqualizer.bandCount, id: \.self) { i in
                    EqFader(band: i)
                }
            }
            CompressorStrip(showCompressor: $showCompressor)
        }
    }
}

struct EqFader: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let band: Int
    var body: some View {
        let accent = vm.accent.tokens
        let freq = MasterEqualizer.bandFrequencies[band]
        let v = vm.eqGains[band]
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                let center = geo.size.height / 2
                let normalized = CGFloat(v / 12)
                let barH = abs(normalized) * (center - 4)
                Rectangle()
                    .fill(accent.dim)
                    .frame(height: barH)
                    .offset(y: normalized >= 0 ? -barH/2 - 4 : barH/2 + 4)
                    .position(x: geo.size.width / 2, y: center)
                VStack {
                    Text(freq >= 1000 ? "\(Int(freq/1000))K" : "\(Int(freq))")
                        .font(SMFont.mono(8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                    Spacer()
                    Text(String(format: "%+.1f", v))
                        .font(SMFont.mono(8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7)).padding(.bottom, 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { g in
                        let center = geo.size.height / 2
                        let normalized = Float(-(g.location.y - center) / center)
                        vm.setEqGain(band: band, db: normalized * 12)
                    }
            )
            .onTapGesture(count: 2) { vm.setEqGain(band: band, db: 0) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompressorStrip: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showCompressor: Bool

    var body: some View {
        let accent = vm.accent.tokens
        HStack(spacing: 8) {
            Text("COMP")
                .font(SMFont.mono(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(accent.hex)
            Toggle("", isOn: $vm.compressorEnabled)
                .labelsHidden()
                .tint(accent.hex)
                .onChange(of: vm.compressorEnabled) { on in vm.audio.compressor.setEnabled(on) }
            ForEach(0..<MultibandCompressor.bandCount, id: \.self) { i in
                GrMeter(band: i)
            }
            Spacer()
            Button { showCompressor = true } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GrMeter: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let band: Int
    @State private var grDb: Float = 0
    let labels = ["LOW", "LO-MID", "HI-MID", "HIGH"]

    var body: some View {
        let accent = vm.accent.tokens
        VStack(spacing: 1) {
            Text(labels[band])
                .font(SMFont.mono(7, weight: .semibold)).tracking(1)
                .foregroundStyle(.white.opacity(0.6))
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                    .frame(width: 22, height: 18)
                Rectangle().fill(accent.hex)
                    .frame(width: 22, height: CGFloat(abs(grDb) * 1.5).clamped(to: 0...18))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
                grDb = vm.audio.compressor.gainReductionDb[band]
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { max(range.lowerBound, min(range.upperBound, self)) }
}
