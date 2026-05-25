import Foundation
import AVFoundation

enum WAVDecoder {
    /// Decode any AVAudioFile-readable file (WAV/PCM/AAC/FLAC/ALAC). Returns mono float32 at `targetSampleRate`.
    static func decode(url: URL, targetSampleRate: Double) -> AudioSample? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let processingFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }

        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: targetSampleRate,
                                             channels: 1,
                                             interleaved: false) else { return nil }

        let ratio = targetSampleRate / processingFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 16)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outFrames) else { return nil }

        guard let converter = AVAudioConverter(from: processingFormat, to: monoFormat) else { return nil }
        var error: NSError?
        var supplied = false
        converter.convert(to: outBuf, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return inBuf
        }
        if error != nil { return nil }

        let n = Int(outBuf.frameLength)
        guard let ptr = outBuf.floatChannelData?[0] else { return nil }
        var arr = [Float](repeating: 0, count: n)
        arr.withUnsafeMutableBufferPointer { dst in
            dst.baseAddress!.update(from: ptr, count: n)
        }
        return AudioSample(data: arr, sampleRate: targetSampleRate)
    }

    /// Decode raw WAV bytes (for external file imports via UIDocumentPicker).
    static func decode(data: Data, targetSampleRate: Double) -> AudioSample? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sm_decode_\(UUID().uuidString).wav")
        do {
            try data.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            return decode(url: tmp, targetSampleRate: targetSampleRate)
        } catch {
            return nil
        }
    }
}
