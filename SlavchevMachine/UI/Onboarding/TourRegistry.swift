import SwiftUI

@MainActor
final class TourRegistry: ObservableObject {
    @Published var targets: [String: CGRect] = [:]
    func setRect(id: String, rect: CGRect) {
        if targets[id] != rect { targets[id] = rect }
    }
}

private struct TargetReporter: ViewModifier {
    let id: String?
    @EnvironmentObject var registry: TourRegistry
    func body(content: Content) -> some View {
        guard let id = id else { return AnyView(content) }
        return AnyView(
            content.background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TargetFramePreferenceKey.self, value: [id: proxy.frame(in: .global)])
                }
            )
            .onPreferenceChange(TargetFramePreferenceKey.self) { dict in
                if let rect = dict[id] { registry.setRect(id: id, rect: rect) }
            }
        )
    }
}

private struct TargetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func tourTarget(_ id: String?) -> some View {
        self.modifier(TargetReporter(id: id))
    }
}
