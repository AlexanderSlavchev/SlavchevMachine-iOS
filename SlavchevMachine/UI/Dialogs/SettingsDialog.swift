import SwiftUI

struct SettingsDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    var showTour: () -> Void
    var showSavedLoops: () -> Void
    @State private var resetArmed: Bool = false
    @State private var stepUp: Int = SettingsStore.tempoStepUp
    @State private var stepDown: Int = SettingsStore.tempoStepDown

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "SETTINGS", accent: accent) {
            VStack(alignment: .leading, spacing: 18) {
                section("APPEARANCE", accent: accent) {
                    HStack(spacing: 12) {
                        ForEach(AccentChoice.allCases, id: \.self) { choice in
                            Button { vm.accent = choice } label: {
                                Circle().fill(choice.tokens.hex)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: choice.tokens.soft, radius: 4)
                                    .overlay(Circle().stroke(vm.accent == choice ? Color.white : Color.white.opacity(0.2),
                                                              lineWidth: vm.accent == choice ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                section("BLUETOOTH", accent: accent) {
                    HStack {
                        Text("\(vm.keyController.bindings.count) KEYS BOUND")
                            .font(SMFont.mono(9))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        if !vm.keyController.bindings.isEmpty {
                            Button(resetArmed ? "TAP AGAIN" : "RESET ALL") {
                                if resetArmed {
                                    vm.keyController.resetAll()
                                    resetArmed = false
                                } else {
                                    resetArmed = true
                                }
                            }
                            .font(SMFont.mono(9, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(resetArmed ? .white : Chassis.recRed)
                            .background(resetArmed ? Chassis.recRed : Color.clear)
                            .overlay(Capsule().stroke(Chassis.recRed, lineWidth: 1))
                            .clipShape(Capsule())
                        }
                    }
                }

                section("BACKGROUND CONTROL", accent: accent) {
                    Text("On iOS, hardware keys only work while the app is in the foreground. To keep audio playing in the background, the app uses iOS's background-audio capability — that part works.")
                        .font(SMFont.mono(9))
                        .foregroundStyle(.white.opacity(0.6))
                }

                section("AUDIO ROUTING", accent: accent) {
                    AudioRoutingSection()
                }

                section("TEMPO STEP", accent: accent) {
                    tempoStepRow(title: "STEP UP +", value: $stepUp, action: .tempoStepUp,
                                 onCommit: { SettingsStore.tempoStepUp = stepUp }, accent: accent)
                    tempoStepRow(title: "STEP DOWN −", value: $stepDown, action: .tempoStepDown,
                                 onCommit: { SettingsStore.tempoStepDown = stepDown }, accent: accent)
                }

                section("TUTORIAL", accent: accent) {
                    PillButton(label: "SHOW TOUR AGAIN", accent: accent) {
                        showTour()
                        dismiss()
                    }
                }

                section("SAVED LOOPS", accent: accent) {
                    PillButton(label: "VIEW & MANAGE", accent: accent) { showSavedLoops() }
                }

                section("ABOUT", accent: accent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SLAVCHEV MACHINE · v0.1.0").font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.6))
                        Text("Scenes save: sequencer + samples + pad mix.\nEQ stays global across scenes.\nBT bindings stay global across scenes.")
                            .font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        } actions: {
            PillButton(label: "CLOSE", primary: true, accent: accent) { dismiss() }
        }
    }

    private func tempoStepRow(title: String, value: Binding<Int>, action: TransportAction,
                              onCommit: @escaping () -> Void, accent: AccentTokens) -> some View {
        let bound = vm.keyController.bindings[action]
        return HStack(spacing: 8) {
            Text(title)
                .font(SMFont.mono(9, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 95, alignment: .leading)
            Stepper("", value: value, in: 1...50).labelsHidden()
            Text("\(value.wrappedValue)").font(SMFont.mono(10)).foregroundStyle(.white).frame(width: 22)
                .onChange(of: value.wrappedValue) { _ in onCommit() }
            Text(bound.flatMap { vm.keyController.keyName(for: $0) } ?? "—")
                .font(SMFont.mono(8)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
            Button(bound == nil ? "LEARN" : "RELEARN") {
                vm.startLearning(action); dismiss()
            }
            .font(SMFont.mono(8, weight: .bold))
            .foregroundStyle(accent.hex)
            if bound != nil {
                Button("×") { vm.keyController.unbind(action) }
                    .font(SMFont.mono(11, weight: .bold))
                    .foregroundStyle(Chassis.recRed)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, accent: AccentTokens, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SMFont.sans(11, weight: .black)).tracking(2)
                .foregroundStyle(accent.soft)
            content()
        }
    }
}

struct DialogShell<Body: View, Actions: View>: View {
    var title: String
    var accent: AccentTokens
    @ViewBuilder var content: () -> Body
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(SMFont.sans(12, weight: .black))
                .tracking(3)
                .foregroundStyle(accent.hex)
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                actions()
            }
        }
        .padding(20)
        .background(Chassis.top)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.dim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}
