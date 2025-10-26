import Foundation
import AVFoundation

/// Computes & caches downsampled waveforms (0...1) for 30s previews.
/// Keyed by a stable per-track key (track.id / uri / name|artist).
@MainActor
final class WaveformStore: ObservableObject {
    static let shared = WaveformStore()

    @Published private(set) var cache: [String: [Float]] = [:]

    private let diskKey = "waveforms.cache.v1"        // key -> base64(Float[])
    private let samplesPerWave = 180                  // visual columns across the strip

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 12
        return URLSession(configuration: c)
    }()

    private init() { loadFromDisk() }

    /// Returns cached waveform or computes+persists it.
    func waveform(for key: String, previewURL: String) async -> [Float]? {
        if let w = cache[key] { return w }
        guard let remote = URL(string: previewURL) else { return nil }

        do {
            // Download to temp file (AVAudioFile prefers file URLs)
            let (data, _) = try await session.data(from: remote)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID().uuidString).mp3")
            try data.write(to: tmp, options: .atomic)

            let w = try await Self.computeWaveform(fileURL: tmp, samples: samplesPerWave)
            try? FileManager.default.removeItem(at: tmp)

            cache[key] = w
            persistToDisk()
            return w
        } catch {
            print("Waveform compute failed:", error)
            return nil
        }
    }

    // MARK: - Computation (non-actor)

    private static func computeWaveform(fileURL: URL, samples: Int) async throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return Array(repeating: 0, count: samples) }

        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        try file.read(into: buf)

        let total = Int(buf.frameLength)
        let channels = Int(format.channelCount)
        guard let ch0 = buf.floatChannelData?[0] else { return Array(repeating: 0, count: samples) }

        let window = max(total / samples, 1)
        var out: [Float] = []
        out.reserveCapacity(samples)

        var i = 0
        while i < total && out.count < samples {
            let end = min(i + window, total)
            var sum: Double = 0
            var n = 0
            var j = i
            while j < end {
                var v = Double(ch0[j])
                if channels > 1, let ch1 = buf.floatChannelData?[1] {
                    v = 0.5 * (v + Double(ch1[j]))
                }
                sum += v * v
                n += 1
                j += 1
            }
            let rms = n > 0 ? sqrt(sum / Double(n)) : 0
            out.append(Float(rms))
            i += window
        }

        // Normalize 0..1 + gentle smoothing
        let maxV = max(out.max() ?? 1e-6, 1e-6)
        var norm = out.map { min(max($0 / maxV, 0), 1) }
        for k in 1..<norm.count { norm[k] = (norm[k-1] * 0.2) + (norm[k] * 0.8) }
        return norm
    }

    // MARK: - Persistence

    private func persistToDisk() {
        var blob: [String: String] = [:]
        for (k, arr) in cache {
            let data = arr.withUnsafeBufferPointer { Data(buffer: $0) }
            blob[k] = data.base64EncodedString()
        }
        UserDefaults.standard.set(blob, forKey: diskKey)
    }

    private func loadFromDisk() {
        guard let blob = UserDefaults.standard.dictionary(forKey: diskKey) as? [String: String] else { return }
        var restored: [String: [Float]] = [:]
        for (k, b64) in blob {
            if let data = Data(base64Encoded: b64) {
                let count = data.count / MemoryLayout<Float>.size
                let arr = data.withUnsafeBytes { ptr in
                    Array(ptr.bindMemory(to: Float.self).prefix(count))
                }
                restored[k] = arr
            }
        }
        cache = restored
    }
}
