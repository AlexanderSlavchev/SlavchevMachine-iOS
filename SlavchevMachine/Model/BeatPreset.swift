import Foundation

enum BeatStyle: String, CaseIterable, Codable {
    case jazz = "JAZZ"
    case pop = "POP"
    case hipHop = "HIPHOP"
    case rnb = "R&B"
    case latin = "LATIN"
    case bossa = "BOSSA"
    case swing = "SWING"
    case sixEight = "6/8"
    case compound = "COMPOUND"
    case waltz = "WALTZ"
    case uneven = "UNEVEN"
    case march = "MARCH"

    var displayName: String { rawValue }
}

struct BeatPreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let name: String
    let bpm: Float
    let style: BeatStyle?       // nil → user preset
    let kitName: String         // for now we encode the kit name only
    let matrix: [[Int]]         // [16][stepCount]
    let timeSignatureString: String

    var timeSignature: TimeSignature { TimeSignature.parse(timeSignatureString) }

    enum CodingKeys: String, CodingKey {
        case id, name, bpm, style, kitName, matrix, timeSignatureString
    }
}

enum UserPresetStore {
    private static var url: URL {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("SlavchevMachine")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_presets.json")
    }

    static func load() -> [BeatPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BeatPreset].self, from: data)) ?? []
    }

    static func save(_ presets: [BeatPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: url)
        }
    }
}
