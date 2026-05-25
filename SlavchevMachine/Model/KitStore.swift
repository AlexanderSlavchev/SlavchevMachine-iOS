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
            for url in contents where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result.append(KitRef(name: url.lastPathComponent, origin: .builtIn))
            }
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: userKitsRoot, includingPropertiesForKeys: nil) {
            for url in contents where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result.append(KitRef(name: url.lastPathComponent, origin: .user))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Returns per-pad primary sample, or nil if the kit doesn't supply one.
    static func sourcesForKit(_ kit: KitRef) -> [PadSampleSource?] {
        let variants = roundRobinSourcesForKit(kit)
        var result: [PadSampleSource?] = Array(repeating: nil, count: AudioConstants.numPads)
        for pad in 0..<AudioConstants.numPads {
            result[pad] = variants[pad]?.first
        }
        return result
    }

    /// Returns per-pad list of round-robin variants (primary + any sibling files whose name
    /// starts with the same base name). Scans the kit folder directly so any kit shape is supported:
    ///   hihat.wav, hihat_sample2.wav, hihat_sample3.wav  → 3 variants for pad 4
    ///   hihat.wav, hihat_alt.wav                          → 2 variants for pad 4
    ///   hihat.wav                                         → 1 variant
    ///
    /// Primary file (exact match `<basename>.wav`) is always at index 0; siblings sorted alphabetically.
    static func roundRobinSourcesForKit(_ kit: KitRef) -> [Int: [PadSampleSource]] {
        var result: [Int: [PadSampleSource]] = [:]
        let root = root(for: kit)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }
        let wavs = contents.filter { $0.pathExtension.lowercased() == "wav" }
        for pad in 0..<AudioConstants.numPads {
            guard let basename = padToFilename[pad] else { continue }
            let primary = root.appendingPathComponent(basename + ".wav")
            var variants: [PadSampleSource] = []
            if FileManager.default.fileExists(atPath: primary.path) {
                variants.append(.localFile(primary))
            }
            // Siblings: <basename>_*.wav (case-sensitive base, anything after underscore).
            let siblingPrefix = basename + "_"
            let siblings = wavs
                .filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(siblingPrefix) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for sib in siblings {
                variants.append(.localFile(sib))
            }
            // Cap at engine limit (3).
            if !variants.isEmpty {
                let limited = Array(variants.prefix(AudioConstants.maxPadLayers))
                result[pad] = limited
                #if DEBUG
                if limited.count > 1 {
                    let label = pad < padLabels.count ? padLabels[pad] : "PAD\(pad)"
                    let names = limited.map { ($0.displayName as NSString).lastPathComponent }.joined(separator: " · ")
                    print("[KitStore] \(kit.name)/\(label) round-robin (\(limited.count)): \(names)")
                }
                #endif
            }
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
