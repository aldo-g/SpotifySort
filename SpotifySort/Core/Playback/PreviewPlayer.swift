import AVFoundation
import Combine

@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    // 20-band simplified “sound profile” for UI visualizer
    @Published var levels: [Float] = Array(repeating: 0, count: 20)

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var currentTask: Task<Void, Never>?
    private var currentTempURL: URL?

    // MARK: - Public API

    /// Stream + play a 30s preview from a remote URL.
    func play(_ urlString: String) {
        guard let remoteURL = URL(string: urlString) else { return }
        stop() // stop anything currently playing and clean up

        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                // Audio session must be touched on main actor.
                try await MainActor.run {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [])
                    try session.setActive(true)
                }

                // Plain download
                let (data, resp) = try await URLSession.shared.data(from: remoteURL)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    print("Preview HTTP error:", http.statusCode, "host=\(remoteURL.host ?? "?")")
                    return
                }

                // Sniff content before we hand to AVAudioFile (prevents 1685348671).
                guard Self.looksLikeMP3(data) else {
                    let head = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("Preview not MP3 (host=\(remoteURL.host ?? "?")). First bytes:", head)
                    return
                }

                // Unique temp file per play to avoid write/read races.
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview-\(UUID().uuidString).mp3")
                try data.write(to: tmp, options: .atomic)

                // Track for cleanup on stop()
                await MainActor.run { self.currentTempURL = tmp }

                // Decode + start engine on main actor.
                let file = try AVAudioFile(forReading: tmp)
                try await MainActor.run { self.startEngine(with: file) }
            } catch is CancellationError {
                // Stopped before completion — nothing to log.
            } catch {
                print("Preview load error:", error)
            }
        }
    }

    /// Stop playback and tear down resources.
    func stop() {
        currentTask?.cancel()
        currentTask = nil

        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()

        // Deactivate the audio session (don’t worry if it was inactive).
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore
        }

        // Remove temp file if any.
        if let url = currentTempURL {
            try? FileManager.default.removeItem(at: url)
            currentTempURL = nil
        }
    }

    // MARK: - Engine setup

    private func startEngine(with file: AVAudioFile) {
        // Fresh engine every time.
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        // Tap for amplitude analysis to drive the UI bars.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: file.processingFormat) { [weak self] buf, _ in
            self?.processBuffer(buf)
        }

        do {
            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()
            print("✅ Preview playing")
        } catch {
            print("Audio engine start failed:", error)
        }
    }

    // MARK: - Amplitude processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let bands = levels.count
        let sliceSize = max(frameLength / bands, 1)
        var newLevels: [Float] = []
        newLevels.reserveCapacity(bands)

        var i = 0
        while i < frameLength {
            let sliceCount = min(sliceSize, frameLength - i)
            var sum: Float = 0
            var j = 0
            while j < sliceCount {
                let s = channelData[i + j]
                sum += s * s
                j += 1
            }
            let rms = sqrt(sum / Float(sliceCount))
            newLevels.append(rms)
            i += sliceSize
        }

        DispatchQueue.main.async { self.levels = newLevels }
    }

    // MARK: - Data sniffing (actor-independent)

    /// Pure function; mark nonisolated so it can be called from detached tasks without `await`.
    nonisolated(unsafe) static func looksLikeMP3(_ data: Data) -> Bool {
        guard data.count > 256 else { return false }

        // ID3 tag header (common)
        if data.starts(with: Data([0x49, 0x44, 0x33])) { // "ID3"
            return true
        }

        // MPEG audio frame sync (0xFFE..)
        let b0 = data[0], b1 = data[1]
        if b0 == 0xFF && (b1 & 0xE0) == 0xE0 {
            return true
        }

        // Obvious non-audio beginnings — rule out early
        if data.starts(with: Data([0x3C, 0x68, 0x74, 0x6D, 0x6C])) { // "<html"
            return false
        }
        if data.starts(with: Data([0x7B, 0x22])) { // JSON "{"
            return false
        }

        return false
    }
}
