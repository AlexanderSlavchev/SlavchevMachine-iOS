import Foundation

enum PadSampleSource {
    case asset(String)       // path relative to bundle Resources/Kits
    case localFile(URL)
    case external(URL)       // security-scoped resource from UIDocumentPicker

    var displayName: String {
        switch self {
        case .asset(let path): return (path as NSString).lastPathComponent
        case .localFile(let url): return url.lastPathComponent
        case .external(let url): return url.lastPathComponent
        }
    }

    func dataValue() -> Data? {
        switch self {
        case .asset(let path):
            let url = Bundle.main.url(forResource: nil, withExtension: nil, subdirectory: "Kits/" + path)
                ?? Bundle.main.bundleURL.appendingPathComponent("Kits/").appendingPathComponent(path)
            return try? Data(contentsOf: url)
        case .localFile(let url):
            return try? Data(contentsOf: url)
        case .external(let url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }
    }

    func decode(targetSampleRate: Double) -> AudioSample? {
        switch self {
        case .asset(let relative):
            let url = Bundle.main.bundleURL.appendingPathComponent("Kits/").appendingPathComponent(relative)
            return WAVDecoder.decode(url: url, targetSampleRate: targetSampleRate)
        case .localFile(let url):
            return WAVDecoder.decode(url: url, targetSampleRate: targetSampleRate)
        case .external(let url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            return WAVDecoder.decode(url: url, targetSampleRate: targetSampleRate)
        }
    }
}
