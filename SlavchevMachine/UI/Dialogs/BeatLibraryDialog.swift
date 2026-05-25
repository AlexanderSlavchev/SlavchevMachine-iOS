import SwiftUI

enum BeatLibraryTab: String, CaseIterable { case defaults = "DEFAULT", user = "USER" }

struct BeatLibraryDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var tab: BeatLibraryTab = .defaults
    @State private var filter: BeatStyle? = nil
    @State private var userPresets: [BeatPreset] = []
    @State private var newPresetName: String = ""
    @State private var armedDeleteId: UUID? = nil

    var defaults: [BeatPreset] {
        if let f = filter { return DefaultPresets.byStyle(f) }
        return DefaultPresets.all
    }

    var body: some View {
        let accent = vm.accent.tokens
        VStack(alignment: .leading, spacing: 12) {
            header(accent: accent)
            tabBar(accent: accent)
            if tab == .defaults {
                styleChips(accent: accent)
                Divider().background(accent.dim)
            }
            if tab == .user {
                userSaveRow(accent: accent)
                Divider().background(accent.dim)
            }
            // Scrollable list — fills remaining height regardless of sheet detent.
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    if tab == .defaults {
                        ForEach(defaults) { p in presetRow(p, accent: accent, isUser: false) }
                    } else {
                        if userPresets.isEmpty {
                            Text("No user presets yet. Save the current sequencer as a preset above.")
                                .font(SMFont.mono(9))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.top, 12)
                        } else {
                            ForEach(userPresets) { p in presetRow(p, accent: accent, isUser: true) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                PillButton(label: "CLOSE", primary: true, accent: accent) { dismiss() }
            }
        }
        .padding(20)
        .background(Chassis.top)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.dim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
        .presentationDetents([.large])     // open as a tall sheet — see entire list
        .onAppear { reloadUser() }
    }

    private func header(accent: AccentTokens) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BEAT LIBRARY")
                .font(SMFont.sans(12, weight: .black))
                .tracking(3)
                .foregroundStyle(accent.hex)
            Spacer()
            let count = tab == .defaults ? defaults.count : userPresets.count
            let total = tab == .defaults ? DefaultPresets.all.count : userPresets.count
            Text("\(count) / \(total)")
                .font(SMFont.mono(9, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func tabBar(accent: AccentTokens) -> some View {
        HStack(spacing: 6) {
            ForEach(BeatLibraryTab.allCases, id: \.self) { t in
                Chip(label: t.rawValue, selected: tab == t, accent: accent) { tab = t }
            }
        }
    }

    private func styleChips(accent: AccentTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: "ALL", selected: filter == nil, accent: accent) { filter = nil }
                ForEach(BeatStyle.allCases, id: \.self) { s in
                    let count = DefaultPresets.byStyle(s).count
                    Chip(label: "\(s.displayName) · \(count)",
                         selected: filter == s, accent: accent) { filter = s }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func userSaveRow(accent: AccentTokens) -> some View {
        HStack {
            TextField("Name your beat…", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .font(SMFont.mono(10))
            PillButton(label: "SAVE", primary: true, accent: accent) {
                let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let preset = vm.snapshotAsBeatPreset(name: trimmed)
                var list = UserPresetStore.load()
                list.insert(preset, at: 0)
                UserPresetStore.save(list)
                newPresetName = ""
                reloadUser()
            }
        }
    }

    private func presetRow(_ p: BeatPreset, accent: AccentTokens, isUser: Bool) -> some View {
        HStack {
            Button {
                vm.loadBeatPreset(p); dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                            .font(SMFont.mono(11, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(p.style?.displayName ?? "USER") · \(Int(p.bpm)) BPM · \(p.timeSignatureString)")
                            .font(SMFont.mono(8))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    if !isUser {
                        Image(systemName: "chevron.right").foregroundStyle(accent.soft)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isUser {
                Button(armedDeleteId == p.id ? "CONFIRM" : "×") {
                    if armedDeleteId == p.id {
                        var list = UserPresetStore.load()
                        list.removeAll { $0.id == p.id }
                        UserPresetStore.save(list)
                        armedDeleteId = nil
                        reloadUser()
                    } else {
                        armedDeleteId = p.id
                    }
                }
                .font(SMFont.mono(9, weight: .bold))
                .foregroundStyle(armedDeleteId == p.id ? .white : Chassis.recRed)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(armedDeleteId == p.id ? Chassis.recRed : Color.clear)
                .clipShape(Capsule())
            }
        }
        .overlay(Divider().background(Color.white.opacity(0.05)), alignment: .bottom)
    }

    private func reloadUser() { userPresets = UserPresetStore.load() }
}
