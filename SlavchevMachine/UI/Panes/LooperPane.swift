import SwiftUI

struct LooperPane: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @State private var selectedBand: Int? = nil
    @State private var inputPeak: Float = 0

    var body: some View {
        let accent = vm.accent.tokens
        VStack(spacing: 10) {
            Text("LOOPER · LEVELS & EQ")
                .font(SMFont.mono(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(accent.soft)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                LevelFader(label: "INPUT", db: $vm.looperInputDb, meter: inputPeak) { db in vm.setLooperInputDb(db) }
                LevelFader(label: "OUTPUT", db: $vm.looperOutputDb, meter: nil) { db in vm.setLooperOutputDb(db) }
            }
            LooperEqGraph(selectedBand: $selectedBand)
                .frame(maxHeight: .infinity)
            EqBandStrip(selectedBand: $selectedBand)
            controlsSection
        }
        .onAppear {
            vm.refreshLooperRouting()
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                inputPeak = vm.audio.looper?.consumePeak() ?? 0
            }
        }
    }

    private var controlsSection: some View {
        let accent = vm.accent.tokens
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $vm.looperFollowStop) {
                    Text("STOP WITH SEQUENCER")
                        .font(SMFont.mono(8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .tint(accent.hex)
                Spacer()
            }
            LearnKeyRow(label: "REC KEY", action: .looperRecord, accent: accent)
            LearnKeyRow(label: "STOP KEY", action: .looperStop, accent: accent)

            if vm.looperActiveTracks > 1 {
                Divider().background(accent.dim).padding(.vertical, 2)
                Text("INPUTS · MUTE & LEARN")
                    .font(SMFont.mono(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(Array(0..<vm.looperActiveTracks), id: \.self) { t in
                    LooperInputMuteRow(track: t, accent: accent)
                }
            }
        }
    }
}

/// One routed input: MUTE toggle (affects an already-recorded loop live) + a learnable
/// Bluetooth page-turner key for that mute, mirroring the REC/STOP LearnKeyRow.
struct LooperInputMuteRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let track: Int
    let accent: AccentTokens

    var body: some View {
        let muted = vm.looperTrackMuted[track]
        let action = TransportAction.looperMute(track: track)
        let bound = action.flatMap { vm.keyController.bindings[$0] }
        HStack(spacing: 8) {
            Button {
                vm.toggleLooperMute(track)
            } label: {
                Text(muted ? "MUTED" : "MUTE")
                    .font(SMFont.mono(8, weight: .bold))
                    .tracking(1)
                    .frame(width: 52)
                    .padding(.vertical, 5)
                    .foregroundStyle(muted ? .white : accent.hex)
                    .background(muted ? Chassis.recRed : accent.dim)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Text(vm.looperTrackLabel(track))
                .font(SMFont.mono(9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(bound.flatMap { vm.keyController.keyName(for: $0) } ?? "—")
                .font(SMFont.mono(8))
                .foregroundStyle(bound != nil ? accent.hex : .white.opacity(0.4))
            if let action = action {
                Button(bound == nil ? "LEARN" : "RELEARN") {
                    vm.startLearning(action)
                }
                .font(SMFont.mono(8, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(accent.hex)
                .background(accent.dim)
                .clipShape(Capsule())
                if bound != nil {
                    Button { vm.keyController.unbind(action) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Chassis.recRed)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Bind-a-Bluetooth-key row for looper REC / STOP — opens TransportLearnOverlay via VM.
struct LearnKeyRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let label: String
    let action: TransportAction
    let accent: AccentTokens

    var body: some View {
        let bound = vm.keyController.bindings[action]
        HStack(spacing: 8) {
            Text(label)
                .font(SMFont.mono(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            Text(bound.flatMap { vm.keyController.keyName(for: $0) } ?? "—")
                .font(SMFont.mono(9))
                .foregroundStyle(bound != nil ? accent.hex : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(bound == nil ? "LEARN" : "RELEARN") {
                vm.startLearning(action)
            }
            .font(SMFont.mono(8, weight: .bold))
            .tracking(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(accent.hex)
            .background(accent.dim)
            .clipShape(Capsule())
            if bound != nil {
                Button { vm.keyController.unbind(action) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Chassis.recRed)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LevelFader: View {
    let label: String
    @Binding var db: Float
    let meter: Float?
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(SMFont.mono(9, weight: .bold)).tracking(2).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(String(format: "%+.1f dB", db)).font(SMFont.mono(9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            if let m = meter {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(m > 0.95 ? Color.red : Color.green)
                            .frame(width: CGFloat(min(m, 1)) * geo.size.width, height: 4)
                    }
                }
                .frame(height: 4)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    let x = (CGFloat(db) + 24) / 36 * geo.size.width
                    Circle().fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: max(6, min(geo.size.width - 6, x)), y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let normalized = max(0, min(1, g.location.x / geo.size.width))
                            let newDb = Float(normalized * 36 - 24)
                            db = max(-24, min(12, newDb))
                            onChange(db)
                        }
                )
                .onTapGesture(count: 2) { db = 0; onChange(0) }
            }
            .frame(height: 18)
        }
    }
}

struct EqBandStrip: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var selectedBand: Int?
    var body: some View {
        let accent = vm.accent.tokens
        if let i = selectedBand {
            let b = vm.looperEqBands[i]
            VStack(spacing: 6) {
                HStack {
                    Text("BAND \(i+1) · \(Int(b.freqHz)) Hz")
                        .font(SMFont.mono(9, weight: .bold))
                        .foregroundStyle(accent.hex)
                    if b.shape != .lowCut && b.shape != .highCut {
                        Text(String(format: "· %+.1f dB", b.gainDb))
                            .font(SMFont.mono(9)).foregroundStyle(accent.hex)
                    }
                    Spacer()
                    Button("REMOVE") {
                        var cfg = b; cfg.enabled = false
                        vm.setLooperEqBand(i, cfg)
                        selectedBand = nil
                    }
                    .font(SMFont.mono(9, weight: .bold))
                    .foregroundStyle(Chassis.recRed)
                }
                HStack {
                    ForEach(EqShape.allCases, id: \.self) { shape in
                        Chip(label: shape.label, selected: b.shape == shape, accent: accent) {
                            var cfg = b; cfg.shape = shape
                            vm.setLooperEqBand(i, cfg)
                        }
                    }
                }
                HStack {
                    Text("Q").font(SMFont.mono(9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { Double(b.q) }, set: { v in
                        var cfg = b; cfg.q = Float(v)
                        vm.setLooperEqBand(i, cfg)
                    }), in: 0.3...10)
                    .tint(accent.hex)
                    Text(String(format: "%.1f", b.q)).font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Double-tap the graph to add an EQ band.")
                .font(SMFont.mono(9))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LooperEqGraph: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var selectedBand: Int?
    private let gainMax: Float = 15
    private let fMin: Float = 20, fMax: Float = 20000

    var body: some View {
        let accent = vm.accent.tokens
        GeometryReader { geo in
            ZStack {
                // Grid
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    for f in [50, 100, 500, 1000, 5000, 10000] {
                        let x = xFor(freq: Float(f), w: w)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                        ctx.stroke(p, with: .color(Color.white.opacity(0.06)))
                    }
                    var zero = Path()
                    zero.move(to: CGPoint(x: 0, y: h/2))
                    zero.addLine(to: CGPoint(x: w, y: h/2))
                    ctx.stroke(zero, with: .color(Color.white.opacity(0.14)))

                    // Curve
                    var path = Path()
                    let samples = 140
                    for s in 0...samples {
                        let x = w * CGFloat(s) / CGFloat(samples)
                        let f = freqFor(x: x, w: w)
                        var db: Float = 0
                        for band in vm.looperEqBands where band.enabled {
                            let c = ParametricEqHelper.coeffs(for: band, fs: vm.audio.sampleRate)
                            db += BiquadDesign.magnitudeDb(coeffs: c, freq: f, fs: vm.audio.sampleRate)
                        }
                        let y = yFor(db: db, h: h)
                        if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(accent.bright), lineWidth: 2)
                }
                // Band nodes
                ForEach(0..<6, id: \.self) { i in
                    let b = vm.looperEqBands[i]
                    if b.enabled {
                        let x = xFor(freq: b.freqHz, w: geo.size.width)
                        let y = (b.shape == .lowCut || b.shape == .highCut) ? geo.size.height/2 : yFor(db: b.gainDb, h: geo.size.height)
                        Circle()
                            .fill(Chassis.body)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(selectedBand == i ? accent.bright : accent.hex, lineWidth: selectedBand == i ? 2.5 : 1.5))
                            .position(x: x, y: y)
                            .gesture(
                                DragGesture()
                                    .onChanged { g in
                                        var cfg = b
                                        cfg.freqHz = freqFor(x: g.location.x, w: geo.size.width)
                                        if cfg.shape != .lowCut && cfg.shape != .highCut {
                                            cfg.gainDb = dbFor(y: g.location.y, h: geo.size.height)
                                        }
                                        vm.setLooperEqBand(i, cfg)
                                    }
                            )
                            .onTapGesture(count: 2) {
                                var cfg = b; cfg.enabled = false
                                vm.setLooperEqBand(i, cfg)
                                if selectedBand == i { selectedBand = nil }
                            }
                            .onTapGesture { selectedBand = i }
                    }
                }
            }
            .background(Chassis.iconBtnGradient)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { loc in
                addBand(at: loc, in: geo.size)
            }
            .onTapGesture { selectedBand = nil }
        }
    }

    private func addBand(at loc: CGPoint, in size: CGSize) {
        if let i = vm.looperEqBands.firstIndex(where: { !$0.enabled }) {
            var cfg = EqBandConfig()
            cfg.shape = .bell
            cfg.q = 1
            cfg.freqHz = freqFor(x: loc.x, w: size.width)
            cfg.gainDb = dbFor(y: loc.y, h: size.height)
            cfg.enabled = true
            vm.setLooperEqBand(i, cfg)
            selectedBand = i
        }
    }

    private func xFor(freq f: Float, w: CGFloat) -> CGFloat {
        CGFloat(log10f(max(f / fMin, 1e-3)) / 3) * w
    }
    private func freqFor(x: CGFloat, w: CGFloat) -> Float {
        fMin * powf(10, Float(3 * x / max(w, 1)))
    }
    private func yFor(db: Float, h: CGFloat) -> CGFloat {
        h / 2 - CGFloat(db / gainMax) * (h / 2)
    }
    private func dbFor(y: CGFloat, h: CGFloat) -> Float {
        Float((h/2 - y) / (h/2)) * gainMax
    }
}

enum ParametricEqHelper {
    static func coeffs(for band: EqBandConfig, fs: Float) -> BiquadCoeffs {
        switch band.shape {
        case .bell:      return BiquadDesign.peak(fs: fs, freq: band.freqHz, gainDb: band.gainDb, q: band.q)
        case .lowShelf:  return BiquadDesign.lowShelf(fs: fs, freq: band.freqHz, gainDb: band.gainDb, q: band.q)
        case .highShelf: return BiquadDesign.highShelf(fs: fs, freq: band.freqHz, gainDb: band.gainDb, q: band.q)
        case .lowCut:    return BiquadDesign.highPass(fs: fs, freq: band.freqHz, q: band.q)
        case .highCut:   return BiquadDesign.lowPass(fs: fs, freq: band.freqHz, q: band.q)
        }
    }
}
