import Foundation

struct LoopEntry: Identifiable {
    let id = UUID()
    let setlist: String
    let scene: String
    let bytes: Int
}

enum SceneStore {
    static let setlistsDir = "setlists"

    private static var rootURL: URL {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("SlavchevMachine")
            .appendingPathComponent(setlistsDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.unicodeScalars
            .map { bad.contains($0) ? "_" : String($0) }.joined()
        return String(cleaned.prefix(48)).trimmingCharacters(in: .whitespaces)
    }

    static func listSetlists() -> [String] {
        (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted() ?? []
    }

    static func listScenes(setlist: String) -> [String] {
        let url = rootURL.appendingPathComponent(setlist)
        let orderURL = url.appendingPathComponent("order.json")
        if let data = try? Data(contentsOf: orderURL),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr
        }
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted() ?? []
    }

    @discardableResult
    static func createSetlist(name: String) -> Bool {
        let clean = sanitize(name)
        guard !clean.isEmpty else { return false }
        let url = rootURL.appendingPathComponent(clean)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch { return false }
    }

    @discardableResult
    static func deleteSetlist(name: String) -> Bool {
        let url = rootURL.appendingPathComponent(name)
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    @discardableResult
    static func deleteScene(setlist: String, name: String) -> Bool {
        let url = rootURL.appendingPathComponent(setlist).appendingPathComponent(name)
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    @discardableResult
    static func reorderScenes(setlist: String, order: [String]) -> Bool {
        let url = rootURL.appendingPathComponent(setlist).appendingPathComponent("order.json")
        do {
            try JSONEncoder().encode(order).write(to: url)
            return true
        } catch { return false }
    }

    @discardableResult
    static func saveScene(setlist: String, scene: SceneSnapshot, padSources: [PadSampleSource?], looperPcm: [Float]? = nil) -> Bool {
        let cleanSet = sanitize(setlist)
        let cleanScene = sanitize(scene.name)
        guard !cleanSet.isEmpty, !cleanScene.isEmpty else { return false }
        let setURL = rootURL.appendingPathComponent(cleanSet)
        let sceneURL = setURL.appendingPathComponent(cleanScene)
        try? FileManager.default.removeItem(at: sceneURL)
        do {
            try FileManager.default.createDirectory(at: sceneURL, withIntermediateDirectories: true)
            let json = try JSONEncoder().encode(scene)
            try json.write(to: sceneURL.appendingPathComponent("scene.json"))
            // Pad WAVs.
            for (i, src) in padSources.enumerated() where src != nil {
                let dst = sceneURL.appendingPathComponent(String(format: "pad_%02d.wav", i))
                if let data = src?.dataValue() {
                    try data.write(to: dst)
                }
            }
            // Loop PCM.
            if let pcm = looperPcm, !pcm.isEmpty {
                let dst = sceneURL.appendingPathComponent("looper.pcm")
                pcm.withUnsafeBufferPointer { bp in
                    let data = Data(buffer: bp)
                    try? data.write(to: dst)
                }
            }
            return true
        } catch {
            return false
        }
    }

    static func loadScene(setlist: String, name: String) -> (scene: SceneSnapshot, padSources: [PadSampleSource?])? {
        let sceneURL = rootURL.appendingPathComponent(setlist).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: sceneURL.appendingPathComponent("scene.json")) else { return nil }
        guard var scene = try? JSONDecoder().decode(SceneSnapshot.self, from: data) else { return nil }
        if scene.drumsMatrixB == nil {
            scene.drumsMatrixB = PatternVariation.deriveBSection(scene.drumsMatrix)
        }
        var sources: [PadSampleSource?] = Array(repeating: nil, count: AudioConstants.numPads)
        for i in 0..<AudioConstants.numPads {
            let wavURL = sceneURL.appendingPathComponent(String(format: "pad_%02d.wav", i))
            if FileManager.default.fileExists(atPath: wavURL.path) {
                sources[i] = .localFile(wavURL)
            }
        }
        return (scene, sources)
    }

    static func loadLooperPcm(setlist: String, name: String) -> [Float]? {
        let url = rootURL.appendingPathComponent(setlist).appendingPathComponent(name).appendingPathComponent("looper.pcm")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        var arr = [Float](repeating: 0, count: count)
        arr.withUnsafeMutableBufferPointer { bp in
            _ = data.copyBytes(to: bp)
        }
        return arr
    }

    static func listLoops() -> [LoopEntry] {
        var results: [LoopEntry] = []
        for setlist in listSetlists() {
            for scene in listScenes(setlist: setlist) {
                let url = rootURL.appendingPathComponent(setlist).appendingPathComponent(scene).appendingPathComponent("looper.pcm")
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int {
                    results.append(LoopEntry(setlist: setlist, scene: scene, bytes: size))
                }
            }
        }
        return results
    }

    @discardableResult
    static func deleteLoop(setlist: String, scene: String) -> Bool {
        let sceneURL = rootURL.appendingPathComponent(setlist).appendingPathComponent(scene)
        let pcmURL = sceneURL.appendingPathComponent("looper.pcm")
        try? FileManager.default.removeItem(at: pcmURL)
        // Mark hasLoop = false in scene.json.
        let jsonURL = sceneURL.appendingPathComponent("scene.json")
        if let data = try? Data(contentsOf: jsonURL),
           var s = try? JSONDecoder().decode(SceneSnapshot.self, from: data) {
            s.looper?.hasLoop = false
            if let newData = try? JSONEncoder().encode(s) {
                try? newData.write(to: jsonURL)
            }
        }
        return true
    }
}
