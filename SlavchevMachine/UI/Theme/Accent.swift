import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct AccentTokens {
    let base: UInt32
    let hex: Color
    let bright: Color
    let soft: Color
    let dim: Color

    init(base: UInt32) {
        self.base = base
        self.hex = Color(hex: base)
        self.bright = Color(hex: base, alpha: 0.95)
        self.soft = Color(hex: base, alpha: 0.55)
        self.dim = Color(hex: base, alpha: 0.18)
    }
}

extension AccentChoice {
    var tokens: AccentTokens {
        switch self {
        case .cyan:    return AccentTokens(base: 0x22E6FF)
        case .green:   return AccentTokens(base: 0x22FFA0)
        case .fuchsia: return AccentTokens(base: 0xFF44C8)
        }
    }
}

enum Chassis {
    static let top = Color(hex: 0x16191E)
    static let mid = Color(hex: 0x0C0D10)
    static let bot = Color(hex: 0x08090B)
    static let body = Color(hex: 0x0A0B0D)

    static let padIdleA = Color(hex: 0x20242B)
    static let padIdleB = Color(hex: 0x14171C)
    static let padPressedA = Color(hex: 0x14161A)
    static let padPressedB = Color(hex: 0x1A1D22)

    static let oledA = Color(hex: 0x07090C)
    static let oledB = Color(hex: 0x0B1116)
    static let oledC = Color(hex: 0x060A0E)

    static let iconBtnA = Color(hex: 0x20242B)
    static let iconBtnB = Color(hex: 0x141619)

    static let recRed = Color(hex: 0xFF4060)
    static let playGreen = Color(hex: 0x22FFA0)

    static let chassisGradient = LinearGradient(
        colors: [top, mid, bot],
        startPoint: .top, endPoint: .bottom
    )

    static let padIdleGradient = LinearGradient(
        colors: [padIdleA, padIdleB],
        startPoint: .top, endPoint: .bottom
    )

    static let oledGradient = LinearGradient(
        colors: [oledA, oledB, oledC],
        startPoint: .top, endPoint: .bottom
    )

    static let iconBtnGradient = LinearGradient(
        colors: [iconBtnA, iconBtnB],
        startPoint: .top, endPoint: .bottom
    )
}
