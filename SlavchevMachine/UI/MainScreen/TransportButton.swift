import SwiftUI

/// Circular transport button.
/// Tap action via Button; long-press uses a simultaneous gesture so it never gets eaten by the
/// Button's tap handler or the press-visual drag.
struct TransportButton: View {
    enum Kind { case play, stop, rec, neutral
        var on: Color {
            switch self {
            case .play: return Color(hex: 0x22FFA0)
            case .stop: return .white
            case .rec:  return Color(hex: 0xFF4060)
            case .neutral: return .white
            }
        }
        var glow: Color {
            switch self {
            case .play: return Color(hex: 0x22FFA0, alpha: 0.6)
            case .stop: return Color.white.opacity(0.4)
            case .rec:  return Color(hex: 0xFF4060, alpha: 0.6)
            case .neutral: return Color.white.opacity(0.2)
            }
        }
    }

    var kind: Kind
    var active: Bool
    var size: CGFloat = 50
    var icon: String
    var label: String? = nil
    var action: () -> Void
    var onLongPress: (() -> Void)? = nil

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x20242B), Color(hex: 0x141619)],
                        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)
                    ))
                if active {
                    Circle()
                        .strokeBorder(kind.on, lineWidth: 1.5)
                        .shadow(color: kind.glow, radius: 12)
                        .shadow(color: kind.glow.opacity(0.6), radius: 22)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                }
                Image(systemName: icon)
                    .font(.system(size: size * 0.30, weight: .heavy))
                    .foregroundStyle(active ? kind.on : Color.white.opacity(0.55))
                if let label = label {
                    Text(label)
                        .font(SMFont.mono(7, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(active ? kind.on.opacity(0.9) : Color.white.opacity(0.45))
                        .offset(y: size * 0.32)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 0.94 : 1)
            .shadow(color: Color.black.opacity(active ? 0 : 0.6), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        // Simultaneous so the tap (Button) and the long-press both work cleanly.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress?() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
