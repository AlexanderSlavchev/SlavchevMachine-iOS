import SwiftUI

/// Brand wordmark + utility icons row.
///   - tap wordmark → Settings
///   - music-note icon → Beat Library (65 default beats + user presets)
///   - rectangle-stack icon → Scene Library
///   - gear icon → Settings
///   - accent dot → cycle accent
struct BrandAndUtilityRow: View {
    @EnvironmentObject var vm: DrumMachineViewModel
    @Binding var showSettings: Bool
    @Binding var showScenes: Bool
    @Binding var showBeats: Bool

    var body: some View {
        let accent = vm.accent.tokens
        HStack(alignment: .center, spacing: 12) {
            Button { showSettings = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SLAVCHEV")
                        .font(SMFont.mono(9, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text("MACHINE")
                        .font(SMFont.sans(18, weight: .black))
                        .tracking(-0.4)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, accent.hex],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            .buttonStyle(.plain)
            .tourTarget("brand")

            Spacer()

            CircularIconButton(systemName: "music.note.list") { showBeats = true }
            CircularIconButton(systemName: "rectangle.stack") { showScenes = true }
                .tourTarget("scene_library_icon")
            CircularIconButton(systemName: "gearshape") { showSettings = true }
            Button { vm.cycleAccent() } label: {
                Circle()
                    .fill(accent.hex)
                    .frame(width: 14, height: 14)
                    .shadow(color: accent.soft, radius: 4)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
    }
}

struct CircularIconButton: View {
    var systemName: String
    var size: CGFloat = 32
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(LinearGradient(
                        colors: [Color(hex: 0x20242B), Color(hex: 0x141619)],
                        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)
                    ))
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 7, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
