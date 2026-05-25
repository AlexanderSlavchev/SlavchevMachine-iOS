import SwiftUI

struct MultibandCompressorDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss

    private let bandLabels = ["LOW", "LO-MID", "HI-MID", "HIGH"]

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "MULTIBAND COMP · 4 BAND", accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                presetRow(accent: accent)
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in bandColumn(i, accent: accent) }
                }
                masterRow(accent: accent)
            }
        } actions: {
            PillButton(label: "DONE", primary: true, accent: accent) { dismiss() }
        }
    }

    private func presetRow(accent: AccentTokens) -> some View {
        HStack {
            ForEach(["PUNCH", "GLUE", "TIGHT LOW", "FAT BEAT"], id: \.self) { name in
                Chip(label: name, selected: false, accent: accent) { applyPreset(name) }
            }
        }
    }

    private func bandColumn(_ i: Int, accent: AccentTokens) -> some View {
        let comp = vm.audio.compressor
        let band = comp.bands[i]
        return VStack(spacing: 6) {
            Text(bandLabels[i]).font(SMFont.mono(11, weight: .bold)).tracking(2).foregroundStyle(accent.hex)
            paramSlider("THR", value: band.thresholdDb, range: -60...0, fmt: "%.0f") { comp.setBand(i, threshold: $0) }
            paramSlider("RNG", value: band.rangeDb, range: -30...15, fmt: "%.0f") { comp.setBand(i, range: $0) }
            paramSlider("ATK", value: band.attackMs, range: 0.5...120, fmt: "%.0f") { comp.setBand(i, attack: $0) }
            paramSlider("REL", value: band.releaseMs, range: 10...1000, fmt: "%.0f") { comp.setBand(i, release: $0) }
            paramSlider("MKP", value: band.makeupDb, range: -12...12, fmt: "%.1f") { comp.setBand(i, makeup: $0) }
            HStack {
                Toggle("S", isOn: Binding(get: { band.solo }, set: { comp.setBand(i, solo: $0) }))
                    .toggleStyle(.button).font(SMFont.mono(8))
                Toggle("B", isOn: Binding(get: { band.bypass }, set: { comp.setBand(i, bypass: $0) }))
                    .toggleStyle(.button).font(SMFont.mono(8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func paramSlider(_ name: String, value: Float, range: ClosedRange<Float>, fmt: String, onChange: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 2) {
            Text(name).font(SMFont.mono(8, weight: .bold)).foregroundStyle(.white.opacity(0.65))
            Slider(value: Binding(get: { Double(value) }, set: { onChange(Float($0)) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
            Text(String(format: fmt, value)).font(SMFont.mono(8)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func masterRow(accent: AccentTokens) -> some View {
        let comp = vm.audio.compressor
        return VStack(spacing: 8) {
            paramSlider("OUTPUT", value: comp.outputGainDb, range: -18...18, fmt: "%+.1f dB") { comp.setOutputGain(db: $0) }
            HStack {
                paramSlider("XOVER 1", value: comp.crossoverHz[0], range: 40...500, fmt: "%.0f") { comp.setCrossover(0, hz: $0) }
                paramSlider("XOVER 2", value: comp.crossoverHz[1], range: 300...3000, fmt: "%.0f") { comp.setCrossover(1, hz: $0) }
                paramSlider("XOVER 3", value: comp.crossoverHz[2], range: 2000...12000, fmt: "%.0f") { comp.setCrossover(2, hz: $0) }
            }
        }
    }

    private func applyPreset(_ name: String) {
        let comp = vm.audio.compressor
        switch name {
        case "PUNCH":
            comp.setOutputGain(db: 1); comp.setCrossover(0, hz: 110); comp.setCrossover(1, hz: 800); comp.setCrossover(2, hz: 5000)
            apply(0, t: -22, r: -5, a: 30, re: 180, m: 1)
            apply(1, t: -22, r: -4, a: 35, re: 160, m: 0.5)
            apply(2, t: -20, r: -3, a: 25, re: 120, m: 0)
            apply(3, t: -24, r: -3, a: 15, re: 90, m: 0)
        case "GLUE":
            comp.setOutputGain(db: 1); comp.setCrossover(0, hz: 120); comp.setCrossover(1, hz: 750); comp.setCrossover(2, hz: 5500)
            apply(0, t: -24, r: -4, a: 20, re: 200, m: 1)
            apply(1, t: -24, r: -4, a: 20, re: 200, m: 1)
            apply(2, t: -24, r: -4, a: 20, re: 200, m: 0.5)
            apply(3, t: -26, r: -3, a: 15, re: 150, m: 0)
        case "TIGHT LOW":
            comp.setOutputGain(db: 1.5); comp.setCrossover(0, hz: 90); comp.setCrossover(1, hz: 600); comp.setCrossover(2, hz: 5000)
            apply(0, t: -28, r: -10, a: 12, re: 140, m: 2)
            apply(1, t: -24, r: -7, a: 18, re: 130, m: 1)
            apply(2, t: -22, r: -3, a: 25, re: 110, m: 0)
            apply(3, t: -26, r: -2, a: 15, re: 90, m: 0)
        case "FAT BEAT":
            comp.setOutputGain(db: 2); comp.setCrossover(0, hz: 120); comp.setCrossover(1, hz: 850); comp.setCrossover(2, hz: 6000)
            apply(0, t: -30, r: -12, a: 8, re: 120, m: 3)
            apply(1, t: -28, r: -10, a: 6, re: 110, m: 2.5)
            apply(2, t: -26, r: -8, a: 5, re: 90, m: 2)
            apply(3, t: -28, r: -6, a: 8, re: 80, m: 1.5)
        default: break
        }
    }

    private func apply(_ i: Int, t: Float, r: Float, a: Float, re: Float, m: Float) {
        let comp = vm.audio.compressor
        comp.setBand(i, threshold: t); comp.setBand(i, range: r); comp.setBand(i, attack: a)
        comp.setBand(i, release: re); comp.setBand(i, makeup: m)
    }
}
