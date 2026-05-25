import SwiftUI

/// Recessed OLED-style panel.
/// Visual spec (from design):
/// - Vertical gradient #07090c → #0b1116 (60%) → #060a0e
/// - Repeating 3px scanline texture at α=0.03, overlay blend
/// - Inset highlight + inset border + drop shadow for the "behind-glass" feel
struct OledPanel<Content: View>: View {
    let accent: AccentTokens
    var radius: CGFloat = 14
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                LinearGradient(stops: [
                    .init(color: Color(hex: 0x07090C), location: 0),
                    .init(color: Color(hex: 0x0B1116), location: 0.6),
                    .init(color: Color(hex: 0x060A0E), location: 1.0),
                ], startPoint: .top, endPoint: .bottom)
            )
            .overlay(ScanlineOverlay().allowsHitTesting(false))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: Color.black.opacity(0.5), radius: 14, x: 0, y: 4)
    }
}

/// Faint repeating 3px scanlines (1px line + 2px gap) at α≈0.03, blended overlay-like.
private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let line = Color.white.opacity(0.03)
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(line), lineWidth: 1)
                y += 3
            }
        }
        .blendMode(.overlay)
    }
}

/// LED-bleed text: accent hex foreground with a 6pt soft text-shadow in the accent's soft alpha.
extension Text {
    func ledBleed(_ accent: AccentTokens) -> some View {
        self
            .foregroundStyle(accent.hex)
            .shadow(color: accent.soft, radius: 3, x: 0, y: 0)
            .shadow(color: accent.soft, radius: 6, x: 0, y: 0)
    }
}

// MARK: - Pill + Chip (unchanged usage but updated visuals)

struct PillButton: View {
    var label: String
    var primary: Bool = false
    var danger: Bool = false
    let accent: AccentTokens
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SMFont.mono(10, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(foreground)
                .background(background)
                .overlay(
                    Capsule().stroke(borderColor, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if danger { return .white }
        if primary { return accent.hex }
        return Color.white.opacity(0.85)
    }
    @ViewBuilder private var background: some View {
        if danger { Chassis.recRed }
        else if primary { accent.dim }
        else { Color.white.opacity(0.06) }
    }
    private var borderColor: Color {
        if danger { return Color.white.opacity(0.3) }
        return accent.dim
    }
}

struct Chip: View {
    var label: String
    var selected: Bool
    let accent: AccentTokens
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SMFont.mono(10, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? accent.hex : Color.white.opacity(0.75))
                .background(selected ? accent.dim : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? accent.hex : Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
