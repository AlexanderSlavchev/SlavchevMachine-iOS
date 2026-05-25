import Foundation

struct KitRef: Hashable {
    enum Origin { case builtIn, user }
    let name: String
    let origin: Origin
}

enum KitStore {
    static let filenameToPad: [String: Int] = [
        "kick": 0, "snare": 1, "snare2": 2, "clap": 3,
        "hihat": 4, "hihatOpen": 5, "ride": 6, "crash": 7,
        "tomL": 8, "tomM": 9, "tomHi": 10, "cb": 11,
        "shkr": 12, "perc": 13, "fx1": 14, "fx2": 15,
    ]

    static let padToFilename: [Int: String] = {
        var m: [Int: String] = [:]
        for (k, v) in filenameToPad { m[v] = k }
        return m
    }()

    static let padLabels = [
        "KICK", "SNARE", "RIM", "CLAP",
        "C-HAT", "O-HAT", "RIDE", "CRASH",
        "TOM L", "TOM M", "TOM H", "CB",
        "SHKR", "PERC", "FX 1", "FX 2",
    ]

    static var bundledKitsRoot: URL {
        Bundle.main.bundleURL.appendingPathComponent("Kits")
    }

    static var userKitsRoot: URL {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("SlavchevMachine").appendingPathComponent("kits")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func listKits() -> [KitRef] {
        var result: [KitRef] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: bundledKitsRoot, includingPropertiesForKeys: nil) {
            for url in contents {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    result.append(KitRef(name: url.lastPathComponent, origin: .builtIn))
                }
            }
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: userKitsRoot, includingPropertiesForKeys: nil) {
            for url in contents {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    result.append(KitRef(name: url.lastPathComponent, origin: .user))
                }
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Returns per-pad primary sample, or nil if the kit doesn't supply one.
    static func sourcesForKit(_ kit: KitRef) -> [PadSampleSource?] {
        var result: [PadSampleSource?] = Array(repeating: nil, count: AudioConstants.numPads)
        let root = root(for: kit)
        for pad in 0..<AudioConstants.numPads {
            guard let fname = padToFilename[pad] else { continue }
            let url = root.appendingPathComponent(fname + ".wav")
            if FileManager.default.fileExists(atPath: url.path) {
                result[pad] = .localFile(url)
            }
        }
        return result
    }

    /// Returns per-pad list of (primary + variants) — up to 3 each.
    static func roundRobinSourcesForKit(_ kit: KitRef) -> [Int: [PadSampleSource]] {
        var result: [Int: [PadSampleSource]] = [:]
        let root = root(for: kit)
        for pad in 0..<AudioConstants.numPads {
            guard let fname = padToFilename[pad] else { continue }
            var variants: [PadSampleSource] = []
            let primary = root.appendingPathComponent(fname + ".wav")
            if FileManager.default.fileExists(atPath: primary.path) {
                variants.append(.localFile(primary))
            }
            for suffix in ["_sample2", "_sample3"] {
                let url = root.appendingPathComponent(fname + suffix + ".wav")
                if FileManager.default.fileExists(atPath: url.path) {
                    variants.append(.localFile(url))
                }
            }
            if !variants.isEmpty { result[pad] = variants }
        }
        return result
    }

    private static func root(for kit: KitRef) -> URL {
        switch kit.origin {
        case .builtIn: return bundledKitsRoot.appendingPathComponent(kit.name)
        case .user: return userKitsRoot.appendingPathComponent(kit.name)
        }
    }

    static var defaultKit: KitRef { KitRef(name: "cajon", origin: .builtIn) }
}
