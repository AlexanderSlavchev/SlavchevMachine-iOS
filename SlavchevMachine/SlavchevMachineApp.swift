import SwiftUI

@main
struct SlavchevMachineApp: App {
    @StateObject private var vm = DrumMachineViewModel()

    var body: some Scene {
        WindowGroup {
            DrumMachineScreen()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
                .onAppear { vm.bootstrap() }
                .background(Chassis.body.ignoresSafeArea())
        }
    }
}
