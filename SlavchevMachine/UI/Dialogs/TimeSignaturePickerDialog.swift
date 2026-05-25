import SwiftUI

struct TimeSignaturePickerDialog: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var numerator: Int = 4
    @State private var denominator: Int = 4

    var body: some View {
        let accent = vm.accent.tokens
        DialogShell(title: "TIME SIGNATURE", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                Text("COMMON").font(SMFont.sans(11, weight: .black)).tracking(2).foregroundStyle(accent.soft)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(TimeSignature.common, id: \.self) { ts in
                        Chip(label: ts.format(), selected: ts == vm.timeSignature, accent: accent) {
                            vm.setTimeSignature(ts); dismiss()
                        }
                    }
                }
                Text("CUSTOM").font(SMFont.sans(11, weight: .black)).tracking(2).foregroundStyle(accent.soft)
                HStack {
                    Stepper("N: \(numerator)", value: $numerator, in: 1...32)
                    Picker("D", selection: $denominator) {
                        ForEach(TimeSignature.denominators, id: \.self) { Text("/\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Text("\(TimeSignature(numerator: numerator, denominator: denominator).stepCount) STEPS")
                    .font(SMFont.mono(9)).foregroundStyle(.white.opacity(0.7))
            }
            .onAppear {
                numerator = vm.timeSignature.numerator
                denominator = vm.timeSignature.denominator
            }
        } actions: {
            PillButton(label: "CANCEL", accent: accent) { dismiss() }
            PillButton(label: "APPLY", primary: true, accent: accent) {
                if TimeSignature.isValid(numerator: numerator, denominator: denominator) {
                    vm.setTimeSignature(TimeSignature(numerator: numerator, denominator: denominator))
                    dismiss()
                }
            }
        }
    }
}
