import Foundation

/// Back-loaded fill patterns (content lives in steps 10..15 so the fill stays musical
/// even when triggered late in the bar). Pad mapping mirrors the cajon kit:
///   0 = KICK, 1 = SNARE, 2 = RIM, 7 = CRASH, 8 = TOM L, 10 = TOM H
enum FillPatterns {
    static let kPadKick = 0
    static let kPadSnare = 1
    static let kPadRim = 2
    static let kPadCrash = 7
    static let kPadTomL = 8
    static let kPadTomH = 10
    static let kPadClick = 2   // metronome click sample

    private static let FA = 127, FS = 110, FM = 90, FL = 70, FG = 50

    /// Build a 16-pad × 16-step matrix with only the named rows populated.
    private static func pattern(kick: [Int] = [], snare: [Int] = [], rim: [Int] = [],
                                tomL: [Int] = [], tomH: [Int] = []) -> [[Int]] {
        let steps = 16
        var m = Array(repeating: Array(repeating: 0, count: steps), count: AudioConstants.numPads)
        func place(_ pad: Int, _ row: [Int]) {
            for i in 0..<min(row.count, steps) { m[pad][i] = row[i] }
        }
        place(kPadKick, kick)
        place(kPadSnare, snare)
        place(kPadRim, rim)
        place(kPadTomL, tomL)
        place(kPadTomH, tomH)
        return m
    }

    /// Fill 1 — snare-led: soft ghost notes and rim hits building toward the wrap.
    static let fill1: [[[Int]]] = {
        let FS = Self.FS, FM = Self.FM, FL = Self.FL, FG = Self.FG
        return [
            pattern(snare: [0,0,0,0, 0,0,0,0, 0,0,FM,0, FM,0,FM,0]),
            pattern(
                kick:  [FG,0,0,0, 0,0,0,0, 0,0,0,0, FM,0,0,0],
                snare: [0,0,0,0, 0,0,0,0, 0,0,0,FL, FM,FL,FS,0]
            ),
            pattern(
                snare: [0,0,0,0, 0,0,0,0, 0,0,0,FL, FL,0,FL,0],
                rim:   [0,0,0,0, 0,0,0,0, 0,0,FL,0, 0,FL,0,0]
            ),
        ]
    }()

    /// Fill 2 — tom-led: light tom rolls / step-downs.
    static let fill2: [[[Int]]] = {
        let FM = Self.FM, FL = Self.FL
        return [
            pattern(
                tomL: [0,0,0,0, 0,0,0,0, 0,0,0,0, FM,0,FM,0],
                tomH: [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,FM,0,FL]
            ),
            pattern(
                snare: [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,FL,0,0],
                tomL:  [0,0,0,0, 0,0,0,0, 0,0,0,FL, FM,0,FL,0],
                tomH:  [0,0,0,0, 0,0,0,0, 0,0,FM,0, 0,0,0,0]
            ),
            pattern(
                tomL: [0,0,0,0, 0,0,0,0, 0,0,FL,0, 0,FL,0,FM],
                tomH: [0,0,0,0, 0,0,0,0, 0,0,0,FL, FM,0,FL,0]
            ),
        ]
    }()

    static func randomFill1() -> [[Int]] { fill1.randomElement() ?? fill1[0] }
    static func randomFill2() -> [[Int]] { fill2.randomElement() ?? fill2[0] }
}
