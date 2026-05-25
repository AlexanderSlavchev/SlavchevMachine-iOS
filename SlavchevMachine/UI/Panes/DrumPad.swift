import SwiftUI
import UniformTypeIdentifiers

/// Drum pad.
///
/// Gestures:
///   - Tap / press-and-drag: select pad + trigger sample at velocity from Y position
///                            (v = 0.3 + 0.7 × (y/h), top = soft, bottom = loud).
///   - Long-press (≥ 0.55s): open the file picker. User picks 1–3 audio files; if 2–3 are
///                            picked they become round-robin variants (never two in a row).
///
/// The press gesture uses `simultaneousGesture` for long-press so it doesn't get eaten by
/// the drag (which fires onChanged immediately with `minimumDistance: 0`).
struct DrumPad: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    let padIndex: Int
    @State private var pressed: Bool = false
    @State private var flash: Double = 0
    @State private var showPicker = false
    @State private var pressSuppressed = false   // set when long-press fires; prevents trigger on release

    var body: some View {
        let accent = vm.accent.tokens
        let hasSample = vm.padHasSample[padIndex]
        let isSelected = vm.selectedPad == padIndex
        let label = padIndex < KitStore.padLabels.count ? KitStore.padLabels[padIndex] : "PAD \(padIndex)"
        let glowAlpha = max(flash, pressed ? 0.85 : 0)

        GeometryReader { geo in
            ZStack {
                // Base neumorphic surface
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: pressed
                              ? [Color(hex: 0x14161A), Color(hex: 0x1A1D22)]
                              : [Color(hex: 0x20242B), Color(hex: 0x14171C)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(pressed ? 0 : 0.65),
                            radius: 14, x: 5, y: 5)
                    .shadow(color: Color.white.opacity(pressed ? 0 : 0.025),
                            radius: 6, x: -2, y: -2)

                if pressed {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 3)
                        .blur(radius: 4)
                        .mask(RoundedRectangle(cornerRadius: 14))
                }

                RoundedRectangle(cornerRadius: 14)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.07), .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)

                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 12)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .opacity(pressed ? 0.2 : 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: accent.bright, location: 0),
                                .init(color: accent.soft, location: 0.30),
                                .init(color: .clear, location: 0.70),
                            ],
                            center: UnitPoint(x: 0.5, y: 0.45),
                            startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6
                        )
                    )
                    .blendMode(.screen)
                    .opacity(glowAlpha * 0.7)
                    .padding(4)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accent.hex, lineWidth: 1.6)
                    .shadow(color: accent.soft, radius: 10)
                    .shadow(color: accent.dim, radius: 22)
                    .opacity(glowAlpha)
                    .allowsHitTesting(false)

                if isSelected {
                    Circle()
                        .fill(accent.hex)
                        .frame(width: 6, height: 6)
                        .shadow(color: accent.soft, radius: 4)
                        .padding(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }

                if pressed {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.dim)
                        .frame(height: geo.size.height * 0.35)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }

                Text(label)
                    .font(SMFont.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(glowAlpha > 0.2 ? Color.white : Color.white.opacity(hasSample ? 0.65 : 0.40))
                    .shadow(color: glowAlpha > 0.2 ? accent.bright : .clear, radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
            }
            .scaleEffect(pressed ? 0.965 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Rectangle())
            // Drag gesture — short tap triggers immediately; drag adjusts Y-velocity.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !pressed && !pressSuppressed {
                            pressed = true
                            let h = geo.size.height
                            let y = max(0, min(h, g.location.y))
                            let v = Float(0.3 + 0.7 * (y / h))
                            vm.selectPad(padIndex)
                            vm.triggerPad(padIndex, velocity: v)
                            flash = 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                withAnimation(.easeOut(duration: 0.28)) { flash = 0 }
                            }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        pressSuppressed = false
                    }
            )
            // Long-press as a SIMULTANEOUS gesture so it isn't eaten by the drag.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .onEnded { _ in
                        pressSuppressed = true
                        pressed = false
                        flash = 0
                        showPicker = true
                    }
            )
            .tourTarget(padIndex == 0 ? "drum_pad" : nil)
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [UTType.audio, UTType.wav],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let sources = urls.prefix(AudioConstants.maxPadLayers).map { PadSampleSource.external($0) }
                    vm.assignPad(padIndex, sources: Array(sources))
                }
            }
        }
    }
}

struct PadGrid4x4: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { col in
                        DrumPad(padIndex: row * 4 + col)
                    }
                }
            }
        }
    }
}
