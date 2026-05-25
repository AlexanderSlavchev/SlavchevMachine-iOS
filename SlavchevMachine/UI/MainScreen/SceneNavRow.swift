import SwiftUI

struct SceneNavRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showScenes: Bool
    @State private var scenes: [String] = []

    var body: some View {
        let accent = vm.accent.tokens
        let index = scenes.firstIndex(of: vm.sceneName)
        let canPrev = (index ?? 0) > 0
        let canNext = (index ?? scenes.count) < scenes.count - 1

        HStack {
            navArrow(systemName: "chevron.left", enabled: canPrev,
                     action: { vm.navigateScene(delta: -1); reload() },
                     longPress: { vm.openTransportMenu(for: .previousScene) },
                     accent: accent)

            Spacer()
            Button { showScenes = true } label: {
                VStack(spacing: 2) {
                    Text(vm.sceneName)
                        .font(SMFont.mono(11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text(vm.setlist.isEmpty ? "— NO SETLIST —" : vm.setlist)
                        .font(SMFont.mono(8, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            Spacer()

            navArrow(systemName: "chevron.right", enabled: canNext,
                     action: { vm.navigateScene(delta: 1); reload() },
                     longPress: { vm.openTransportMenu(for: .nextScene) },
                     accent: accent)
        }
        .tourTarget("scene_nav")
        .frame(height: 36)
        .onAppear { reload() }
        .onChange(of: vm.setlist) { _ in reload() }
        .onChange(of: vm.sceneName) { _ in reload() }
    }

    private func navArrow(systemName: String, enabled: Bool,
                          action: @escaping () -> Void,
                          longPress: @escaping () -> Void,
                          accent: AccentTokens) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? accent.hex : accent.hex.opacity(0.25))
                .frame(width: 36, height: 32)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // Long-press always works even when arrow is disabled — so user can bind keys early.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPress() }
        )
    }

    private func reload() {
        scenes = SceneStore.listScenes(setlist: vm.setlist)
    }
}
