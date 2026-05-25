import Foundation

struct SceneEqBand: Codable, Hashable {
    var shape: Int        // EqShape rawValue
    var freqHz: Float
    var gainDb: Float
    var q: Float
    var enabled: Bool
}

struct SceneSnapshot: Codable {
    var name: String
    var bpm: Float
    var humanize: Bool
    var timeSignature: String
    var drumsMatrix: [[Int]]
    var drumsMatrixB: [[Int]]?
    var padVolumes: [Float]
    var padHasSample: [Bool]
    var looper: LooperBlock?

    struct LooperBlock: Codable {
        var inputGainDb: Float
        var outputGainDb: Float
        var followStop: Bool
        var hasLoop: Bool
        var latencyComp: Int
        var barOffsets: [Int]
        var eqBands: [SceneEqBand]
    }
}
