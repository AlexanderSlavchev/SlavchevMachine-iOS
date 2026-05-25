import SwiftUI

struct SavedLoopsDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var loops: [LoopEntry] = []
    @State private var armedDelete: UUID? = nil

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "SAVED LOOPS", accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(loops.count) LOOPS · \(formatBytes(loops.reduce(0) { $0 + $1.bytes }))")
                    .font(SMFont.mono(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(accent.soft)
                ForEach(loops) { loop in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loop.scene).font(SMFont.mono(12, weight: .bold)).foregroundStyle(.white)
                            Text("\(loop.setlist) · \(formatSeconds(loop.bytes)) · \(formatBytes(loop.bytes))")
                                .font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Button(armedDelete == loop.id ? "CONFIRM" : "DELETE") {
                            if armedDelete == loop.id {
                                _ = SceneStore.deleteLoop(setlist: loop.setlist, scene: loop.scene)
                                reload()
                                armedDelete = nil
                            } else {
                                armedDelete = loop.id
                            }
                        }
                        .font(SMFont.mono(9, weight: .bold))
                        .foregroundStyle(armedDelete == loop.id ? .white : Chassis.recRed)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(armedDelete == loop.id ? Chassis.recRed : Color.clear)
                        .overlay(Capsule().stroke(Chassis.recRed, lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        } actions: {
            PillButton(label: "CLOSE", primary: true, accent: accent) { dismiss() }
        }
        .onAppear { reload() }
    }

    private func reload() { loops = SceneStore.listLoops() }
    private func formatBytes(_ b: Int) -> String {
        let mb = Double(b) / 1_048_576
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(b) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(b) B"
    }
    private func formatSeconds(_ bytes: Int) -> String {
        let seconds = Double(bytes) / 4.0 / 48000.0
        return String(format: "%.1fs", seconds)
    }
}
