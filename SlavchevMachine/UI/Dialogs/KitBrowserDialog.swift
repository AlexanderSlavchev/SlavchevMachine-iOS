import SwiftUI

struct KitBrowserDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var kits: [KitRef] = []
    @State private var showSaveAlert = false
    @State private var newKitName = ""
    @State private var armedDelete: String? = nil

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "KIT BROWSER", accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(kits.count) KITS").font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    PillButton(label: "SAVE AS", primary: true, accent: accent) {
                        showSaveAlert = true
                    }
                }
                Divider().background(accent.dim)
                ForEach(kits, id: \.self) { kit in
                    HStack {
                        Button {
                            vm.loadKit(kit); dismiss()
                        } label: {
                            HStack {
                                Text(kit.name).font(SMFont.mono(11, weight: .bold)).foregroundStyle(.white)
                                Spacer()
                                Text(kit.origin == .builtIn ? "BUILT-IN" : "USER")
                                    .font(SMFont.mono(8)).foregroundStyle(accent.soft)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if kit.origin == .user {
                            Button(armedDelete == kit.name ? "CONFIRM" : "×") {
                                if armedDelete == kit.name {
                                    deleteUserKit(kit.name)
                                    armedDelete = nil
                                } else {
                                    armedDelete = kit.name
                                }
                            }
                            .font(SMFont.mono(10, weight: .bold))
                            .foregroundStyle(armedDelete == kit.name ? .white : Chassis.recRed)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(armedDelete == kit.name ? Chassis.recRed : Color.clear)
                            .clipShape(Capsule())
                        }
                    }
                    Divider().background(Color.white.opacity(0.05))
                }
            }
        } actions: {
            PillButton(label: "CLOSE", primary: true, accent: accent) { dismiss() }
        }
        .onAppear { kits = KitStore.listKits() }
        .alert("SAVE CUSTOM KIT", isPresented: $showSaveAlert) {
            TextField("Kit name", text: $newKitName)
            Button("Save") {
                guard !newKitName.isEmpty else { return }
                saveCurrentKit(name: newKitName)
                newKitName = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the currently-loaded pad samples as a new user kit.")
        }
    }

    private func saveCurrentKit(name: String) {
        let dir = KitStore.userKitsRoot.appendingPathComponent(KitStore.sanitize(name))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pad in 0..<AudioConstants.numPads {
            guard let fname = KitStore.padToFilename[pad],
                  let src = vm.padSources[pad],
                  let bytes = src.dataValue() else { continue }
            let dst = dir.appendingPathComponent(fname + ".wav")
            try? bytes.write(to: dst)
        }
        kits = KitStore.listKits()
    }

    private func deleteUserKit(_ name: String) {
        let dir = KitStore.userKitsRoot.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dir)
        kits = KitStore.listKits()
    }
}

extension KitStore {
    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
        return String(cleaned.prefix(32)).trimmingCharacters(in: .whitespaces)
    }
}
