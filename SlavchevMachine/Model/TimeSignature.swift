import Foundation

struct TimeSignature: Hashable, Codable {
    let numerator: Int
    let denominator: Int

    static let `default` = TimeSignature(numerator: 4, denominator: 4)
    static let maxSteps = 32
    static let denominators = [2, 4, 8, 16]

    static let common: [TimeSignature] = [
        .init(numerator: 2, denominator: 4), .init(numerator: 3, denominator: 4),
        .init(numerator: 4, denominator: 4), .init(numerator: 5, denominator: 4),
        .init(numerator: 6, denominator: 4), .init(numerator: 7, denominator: 4),
        .init(numerator: 3, denominator: 8), .init(numerator: 5, denominator: 8),
        .init(numerator: 6, denominator: 8), .init(numerator: 7, denominator: 8),
        .init(numerator: 9, denominator: 8), .init(numerator: 12, denominator: 8),
        .init(numerator: 5, denominator: 16), .init(numerator: 7, denominator: 16),
        .init(numerator: 11, denominator: 16), .init(numerator: 13, denominator: 16),
    ]

    var stepCount: Int {
        min(numerator * 16 / max(denominator, 1), Self.maxSteps)
    }

    var isCompound: Bool {
        denominator >= 8 && numerator >= 6 && numerator % 3 == 0
    }

    var beatGroups: [Int] {
        let unit = 16 / max(denominator, 1)
        if isCompound {
            return Array(repeating: 3 * unit, count: numerator / 3)
        } else if denominator <= 4 || numerator <= 4 {
            return Array(repeating: unit, count: numerator)
        } else {
            // additive — pairs of 2 with a trailing 3 when odd.
            var groups: [Int] = []
            var n = numerator
            while n > 3 {
                groups.append(2 * unit)
                n -= 2
            }
            groups.append(n * unit)
            return groups
        }
    }

    var groupStartSteps: Set<Int> {
        var result: Set<Int> = [0]
        var acc = 0
        for g in beatGroups.dropLast() {
            acc += g
            result.insert(acc)
        }
        return result
    }

    func format() -> String { "\(numerator)/\(denominator)" }

    static func parse(_ text: String?) -> TimeSignature {
        guard let text = text else { return .default }
        let parts = text.split(separator: "/")
        guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]) else { return .default }
        guard isValid(numerator: n, denominator: d) else { return .default }
        return TimeSignature(numerator: n, denominator: d)
    }

    static func isValid(numerator n: Int, denominator d: Int) -> Bool {
        guard denominators.contains(d), n >= 1, n <= 32 else { return false }
        return n * 16 / d <= maxSteps
    }
}
