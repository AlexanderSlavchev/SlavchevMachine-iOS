import SwiftUI

struct ModeSwitcherRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    var body: some View {
        let accent = vm.accent.tokens
        HStack(spacing: 6) {
            ForEach(PaneMode.allCases, id: \.self) { mode in
                Button { vm.paneMode = mode } label: {
                    Text(mode.label)
                        .font(SMFont.sans(10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(vm.paneMode == mode ? accent.hex : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(vm.paneMode == mode ? accent.dim : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(vm.paneMode == mode ? accent.hex : Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .tourTarget("mode_switcher")
    }
}
