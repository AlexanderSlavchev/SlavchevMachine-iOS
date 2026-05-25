import SwiftUI

/// Track / control tabs.
/// Long-press on B / FILL 1 / FILL 2 opens the transport context menu so the user can bind a
/// Bluetooth page-turner key to that action (uses simultaneousGesture so it never gets eaten).
struct TrackTabRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showKits: Bool

    var body: some View {
        HStack(spacing: 6) {
            tab(label: "KIT", sub: "BROWSE", selected: false,
                action: { showKits = true })
            tab(label: "A", sub: "SECTION", selected: vm.activeSection == .a,
                action: { vm.activeSection = .a })
            tab(label: "B", sub: "SECTION", selected: vm.activeSection == .b,
                action: { vm.activeSection = .b },
                longPress: { vm.openTransportMenu(for: .sectionToggle) })
                .tourTarget("section_b")
            tab(label: "FILL 1", sub: "SNARE", selected: vm.armedFill == .one,
                action: { vm.armFill(.one) },
                longPress: { vm.openTransportMenu(for: .fill1) })
                .tourTarget("fill_button")
            tab(label: "FILL 2", sub: "TOM", selected: vm.armedFill == .two,
                action: { vm.armFill(.two) },
                longPress: { vm.openTransportMenu(for: .fill2) })
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func tab(label: String, sub: String, selected: Bool,
                     action: @escaping () -> Void,
                     longPress: (() -> Void)? = nil) -> some View {
        let accent = vm.accent.tokens
        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1C20), Color(hex: 0x131519)],
                                         startPoint: .top, endPoint: .bottom))
                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [accent.dim, .clear],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.bright, lineWidth: 1)
                        .shadow(color: accent.dim, radius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.04), .clear],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(SMFont.sans(13, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                    Text(sub)
                        .font(SMFont.mono(8, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(selected ? accent.hex : Color.white.opacity(0.28))
                }
                .padding(.leading, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(selected ? 0 : 0.5), radius: 5, x: 0, y: 2)
        // Simultaneous long-press — fires after 0.5s without cancelling the Button's tap.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPress?() },
            including: longPress != nil ? .all : .subviews
        )
    }
}
