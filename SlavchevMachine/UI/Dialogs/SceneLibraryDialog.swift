import SwiftUI

private struct CopiedScene { let setlist: String; let scene: String }
private struct CopiedSetlist { let name: String }

struct SceneLibraryDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var query: String = ""
    @State private var setlists: [String] = []
    @State private var scenesBySet: [String: [String]] = [:]
    @State private var saveDialog: SaveRequest? = nil
    @State private var expanded: Set<String> = []
    @State private var newSetlistAlert = false
    @State private var newSetlistName: String = ""
    @State private var armedDelete: String? = nil
    @State private var copiedScene: CopiedScene? = nil
    @State private var copiedSetlist: CopiedSetlist? = nil

    struct SaveRequest: Identifiable { let id = UUID() }

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "SCENE LIBRARY", accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                topControls(accent: accent)
                if filteredSetlists.isEmpty {
                    Text(query.isEmpty
                         ? "No setlists yet. Tap NEW SET to create one, or SAVE to snapshot the current state."
                         : "No matches for \(query).")
                        .font(SMFont.mono(9))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 8)
                }
                ForEach(filteredSetlists, id: \.self) { set in
                    setlistRow(set, accent: accent)
                }
                if let copied = copiedScene {
                    pastePill("Paste scene \"\(copied.scene)\" → current?", accent: accent) {
                        // Paste into selected setlist if any; otherwise show alert.
                        if let target = filteredSetlists.first {
                            pasteScene(copied: copied, into: target)
                        }
                    }
                }
            }
        } actions: {
            PillButton(label: "CLOSE", primary: true, accent: accent) { dismiss() }
        }
        .onAppear { reload() }
        .onChange(of: query) { _ in
            if !query.isEmpty { expanded = Set(filteredSetlists) }
        }
        .sheet(item: $saveDialog) { _ in
            SaveSceneAsDialog { setlist, name, includeLoop in
                let scene = vm.snapshotScene(name: name, includeLoop: includeLoop)
                var srcs = vm.padSources
                for i in 0..<srcs.count where !vm.padHasSample[i] { srcs[i] = nil }
                let tracks = includeLoop ? vm.audio.looper?.exportTracks() : nil
                _ = SceneStore.saveScene(setlist: setlist, scene: scene, padSources: srcs, looperTracks: tracks)
                vm.setlist = setlist
                vm.sceneName = name
                reload()
            }
        }
        .alert("NEW SETLIST", isPresented: $newSetlistAlert) {
            TextField("Name", text: $newSetlistName)
            Button("Create") {
                if !newSetlistName.isEmpty { SceneStore.createSetlist(name: newSetlistName) }
                newSetlistName = ""
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func topControls(accent: AccentTokens) -> some View {
        HStack {
            TextField("Search…", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(SMFont.mono(10))
            PillButton(label: "NEW SET", accent: accent) { newSetlistAlert = true }
            PillButton(label: "SAVE AS", primary: true, accent: accent) {
                saveDialog = SaveRequest()
            }
        }
    }

    @ViewBuilder
    private func setlistRow(_ set: String, accent: AccentTokens) -> some View {
        let scenes = filteredScenes(in: set)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { toggle(set) } label: {
                    Image(systemName: expanded.contains(set) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(accent.hex)
                        .frame(width: 16)
                }.buttonStyle(.plain)
                Text(set).font(SMFont.mono(11, weight: .bold)).foregroundStyle(.white)
                Text("· \(scenes.count)").font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                if let cs = copiedScene {
                    Button("PASTE \(cs.scene)") {
                        pasteScene(copied: cs, into: set)
                    }
                    .font(SMFont.mono(8, weight: .bold))
                    .foregroundStyle(accent.hex)
                }
                Button(armedDelete == "set:" + set ? "CONFIRM" : "×") {
                    if armedDelete == "set:" + set {
                        SceneStore.deleteSetlist(name: set)
                        armedDelete = nil
                        reload()
                    } else {
                        armedDelete = "set:" + set
                    }
                }
                .font(SMFont.mono(10, weight: .bold))
                .foregroundStyle(armedDelete == "set:" + set ? .white : Chassis.recRed)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(armedDelete == "set:" + set ? Chassis.recRed : Color.clear)
                .clipShape(Capsule())
                Button { copiedSetlist = CopiedSetlist(name: set) } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(.white.opacity(0.5))
                }
            }
            if expanded.contains(set) {
                ForEach(scenes, id: \.self) { scene in
                    sceneRow(setlist: set, scene: scene, accent: accent)
                        .padding(.leading, 24)
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(Divider().background(Color.white.opacity(0.05)), alignment: .bottom)
    }

    private func sceneRow(setlist: String, scene: String, accent: AccentTokens) -> some View {
        let isActive = vm.setlist == setlist && vm.sceneName == scene
        return HStack {
            Button {
                if let (s, srcs) = SceneStore.loadScene(setlist: setlist, name: scene) {
                    vm.loadScene(setlist: setlist, scene: s, padSources: srcs)
                    dismiss()
                }
            } label: {
                HStack {
                    Text(scene).font(SMFont.mono(10)).foregroundStyle(.white.opacity(0.85))
                    if isActive {
                        Text("ACTIVE")
                            .font(SMFont.mono(7, weight: .bold)).tracking(1)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(accent.dim)
                            .foregroundStyle(accent.hex)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            Button { copiedScene = CopiedScene(setlist: setlist, scene: scene) } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.white.opacity(0.5)).font(.system(size: 11))
            }
            Button(armedDelete == "scene:\(setlist)/\(scene)" ? "CONFIRM" : "×") {
                let key = "scene:\(setlist)/\(scene)"
                if armedDelete == key {
                    SceneStore.deleteScene(setlist: setlist, name: scene)
                    armedDelete = nil
                    reload()
                } else {
                    armedDelete = key
                }
            }
            .font(SMFont.mono(10, weight: .bold))
            .foregroundStyle(armedDelete == "scene:\(setlist)/\(scene)" ? .white : Chassis.recRed)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(armedDelete == "scene:\(setlist)/\(scene)" ? Chassis.recRed : Color.clear)
            .clipShape(Capsule())
        }
    }

    private func pastePill(_ label: String, accent: AccentTokens, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(SMFont.mono(9, weight: .bold))
            .foregroundStyle(accent.hex)
            .padding(8)
            .background(accent.dim)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func pasteScene(copied: CopiedScene, into target: String) {
        if let (s, srcs) = SceneStore.loadScene(setlist: copied.setlist, name: copied.scene) {
            // New name = original + " (copy)" until unique.
            var newName = s.name
            let existing = SceneStore.listScenes(setlist: target)
            while existing.contains(newName) { newName += " (copy)" }
            var sc = s; sc.name = newName
            _ = SceneStore.saveScene(setlist: target, scene: sc, padSources: srcs, looperTracks: nil)
            reload()
            copiedScene = nil
        }
    }

    private func reload() {
        setlists = SceneStore.listSetlists()
        scenesBySet = Dictionary(uniqueKeysWithValues: setlists.map { ($0, SceneStore.listScenes(setlist: $0)) })
    }

    private var filteredSetlists: [String] {
        let q = query.lowercased()
        if q.isEmpty { return setlists }
        return setlists.filter { set in
            set.lowercased().contains(q) ||
            (scenesBySet[set] ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    private func filteredScenes(in setlist: String) -> [String] {
        let scenes = scenesBySet[setlist] ?? []
        let q = query.lowercased()
        if q.isEmpty || setlist.lowercased().contains(q) { return scenes }
        return scenes.filter { $0.lowercased().contains(q) }
    }

    private func toggle(_ set: String) {
        if expanded.contains(set) { expanded.remove(set) } else { expanded.insert(set) }
    }
}

struct SaveSceneAsDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var setlist: String = ""
    @State private var sceneName: String = ""
    @State private var includeLoop: Bool = true
    var onSave: (String, String, Bool) -> Void

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "SAVE SCENE", accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SETLIST").font(SMFont.sans(11, weight: .bold)).tracking(2).foregroundStyle(accent.soft)
                TextField("Setlist name", text: $setlist).textFieldStyle(.roundedBorder)
                Text("SCENE NAME").font(SMFont.sans(11, weight: .bold)).tracking(2).foregroundStyle(accent.soft)
                TextField("Scene name", text: $sceneName).textFieldStyle(.roundedBorder)
                let hasLoop = vm.audio.looper?.state == .playing || vm.audio.looper?.state == .stopped
                if hasLoop {
                    Toggle("INCLUDE LOOP AUDIO", isOn: $includeLoop).tint(accent.hex)
                }
            }
            .onAppear {
                if setlist.isEmpty { setlist = vm.setlist.isEmpty ? "DEFAULT" : vm.setlist }
                if sceneName.isEmpty { sceneName = vm.sceneName }
            }
        } actions: {
            PillButton(label: "CANCEL", accent: accent) { dismiss() }
            PillButton(label: "SAVE", primary: true, accent: accent) {
                onSave(setlist, sceneName, includeLoop)
                dismiss()
            }
        }
    }
}
