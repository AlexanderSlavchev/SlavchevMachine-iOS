import SwiftUI

struct DrumMachineScreen: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @StateObject var tourRegistry = TourRegistry()
    @State private var showSettings = false
    @State private var showScenes = false
    @State private var showBeatLibrary = false
    @State private var showTimeSig = false
    @State private var showCompressor = false
    @State private var showSavedLoops = false
    @State private var showKitBrowser = false
    @State private var tourActive = !OnboardingStore.hasSeen

    var body: some View {
        let accent = vm.accent.tokens
        ZStack {
            backgroundLayer(accent: accent)
                // Double-tap chassis background cycles accent.
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { vm.cycleAccent() }

            // Invisible responder for hardware-key capture (foreground only).
            KeyCaptureView()
                .frame(width: 0, height: 0)
                .opacity(0)

            VStack(spacing: 14) {
                BrandAndUtilityRow(showSettings: $showSettings, showScenes: $showScenes, showBeats: $showBeatLibrary)
                OledAndTransportRow(showTimeSig: $showTimeSig, showBeatLibrary: $showBeatLibrary)
                SequencerHeader()
                SequencerRow()
                TrackTabRow(showKits: $showKitBrowser)

                paneContainer
                    .frame(maxHeight: .infinity)

                ModeSwitcherRow()
                SceneNavRow(showScenes: $showScenes)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            if vm.keyController.learningAction != nil {
                TransportLearnOverlay()
            }
            if tourActive {
                CoachMarkOverlay(active: $tourActive)
                    .environmentObject(tourRegistry)
            }
        }
        .environmentObject(tourRegistry)
        .sheet(isPresented: $showSettings) {
            SettingsDialog(
                showTour: { tourActive = true; OnboardingStore.reset() },
                showSavedLoops: { showSettings = false; showSavedLoops = true }
            )
        }
        .sheet(isPresented: $showScenes) { SceneLibraryDialog() }
        .sheet(isPresented: $showBeatLibrary) { BeatLibraryDialog() }
        .sheet(isPresented: $showTimeSig) { TimeSignaturePickerDialog() }
        .sheet(isPresented: $showCompressor) { MultibandCompressorDialog() }
        .sheet(isPresented: $showSavedLoops) { SavedLoopsDialog() }
        .sheet(isPresented: $showKitBrowser) { KitBrowserDialog() }
        .sheet(item: $vm.transportMenuFor) { req in
            TransportContextMenu(request: req)
        }
    }

    @ViewBuilder
    private var paneContainer: some View {
        switch vm.paneMode {
        case .pads: PadGrid4x4()
        case .mix: PadMixPane()
        case .eq: MasterEqPane(showCompressor: $showCompressor)
        case .looper: LooperPane()
        }
    }

    private func backgroundLayer(accent: AccentTokens) -> some View {
        ZStack {
            GeometryReader { geo in
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x16191E), location: 0),
                        .init(color: Color(hex: 0x0C0D10), location: 0.65),
                        .init(color: Color(hex: 0x08090B), location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 1.2
                )
                .ignoresSafeArea()
            }
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(colors: [accent.dim, .clear],
                                       center: .center, startRadius: 0, endRadius: 160)
                    )
                    .frame(width: 320, height: 320)
                    .offset(x: geo.size.width - 200, y: -120)
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()
            }
        }
    }
}
