import SwiftUI

enum SMFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension View {
    func tracking2() -> some View { self.tracking(2) }
    func tracking3() -> some View { self.tracking(3) }
}
