import Foundation

/// Derives a musically related B section from an A matrix.
/// Mirrors PatternVariation.deriveBSection in the Android source.
enum PatternVariation {
    static func deriveBSection(_ a: [[Int]]) -> [[Int]] {
        guard let firstRow = a.first else { return a }
        let steps = firstRow.count
        let totalCells = a.count * steps
        let totalHits = a.reduce(0) { $0 + $1.reduce(0) { $0 + ($1 > 0 ? 1 : 0) } }
        let density = totalCells > 0 ? Double(totalHits) / Double(totalCells) : 0

        var b = a.map { $0 }
        if density >= 0.15 {
            // busy → lighter B: drop ~20% of off-beat hits, soften 30%.
            for pad in 0..<b.count {
                for step in 0..<steps where b[pad][step] > 0 && (step % 4 != 0) {
                    let r = Double.random(in: 0..<1)
                    if r < 0.20 { b[pad][step] = 0 }
                    else if r < 0.50 { b[pad][step] = max(20, b[pad][step] - 30) }
                }
            }
        } else if density <= 0.04 {
            // sparse → busier B: add ghost notes on off-beats.
            for pad in 0..<b.count {
                for step in 0..<steps where b[pad][step] == 0 && (step % 2 == 1) {
                    if Double.random(in: 0..<1) < 0.12 { b[pad][step] = 50 }
                }
            }
        } else {
            // moderate → mild variation.
            for pad in 0..<b.count {
                for step in 0..<steps where b[pad][step] > 0 {
                    if Double.random(in: 0..<1) < 0.15 {
                        let delta = Int.random(in: -20...20)
                        b[pad][step] = max(20, min(127, b[pad][step] + delta))
                    }
                }
                for step in 0..<steps where b[pad][step] == 0 && (step % 2 == 1) {
                    if Double.random(in: 0..<1) < 0.08 { b[pad][step] = 50 }
                }
            }
        }
        return b
    }
}
