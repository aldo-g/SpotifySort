import AVFoundation
import Combine
import UIKit

@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    // 20-band levels (kept for potential future visualizers)
    @Published var levels: [Float] = Array(repeating: 0, count: 20)

    // Playback progress (0...1) for the waveform fill
    @Published var progress: Double = 0

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var currentTask: Task<Void, Never>?
    private var currentTempURL: URL?

    private var durationSeconds: Double = 0
    private var displayLink: CADisplayLink?

    // MARK: - Public API

    func play(_ urlString: String) {
        stop() // stop anything currently playing and clean up

        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                // Configure audio session on main actor.
                try await MainActor.run {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [])
                    try session.setActive(true)
                }

                // Download (fail silently if not reachable)
                guard let finalURL = URL(string: urlString) else { return }
                let (data, resp) = try await URLSession.shared.data(from: finalURL)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return
                }

                // Quick sniff to avoid AVAudioFile errors on non-audio bodies
                guard Self.looksLikeMP3(data) else { return }

                // Unique temp file per play
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).mp3")
                try data.write(to: tmp, options: .atomic)
                await MainActor.run { self.currentTempURL = tmp }

                // Decode + start engine on main actor
                let file = try AVAudioFile(forReading: tmp)
                await MainActor.run { self.startEngine(with: file) }
            } catch is CancellationError {
                // Stopped before completion
            } catch {
                // Fail silently
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil

        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()

        stopDisplayLink()
        progress = 0

        // Deactivate session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch { /* ignore */ }

        // Cleanup temp file
        if let url = currentTempURL {
            try? FileManager.default.removeItem(at: url)
            currentTempURL = nil
        }
    }

    // MARK: - Engine setup

    private func startEngine(with file: AVAudioFile) {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        // Tap to keep levels updated (optional; cheap)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: file.processingFormat) { [weak self] buf, _ in
            self?.processBuffer(buf)
        }

        do {
            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()

            durationSeconds = Double(file.length) / file.processingFormat.sampleRate
            startDisplayLink()
        } catch {
            // Silent failure
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

    // MARK: - Progress (CADisplayLink)

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard durationSeconds > 0 else { progress = 0; return }
        if let nodeTime = player.lastRenderTime,
           let pTime = player.playerTime(forNodeTime: nodeTime) {
            let t = Double(pTime.sampleTime) / pTime.sampleRate
            progress = min(max(t / durationSeconds, 0), 1)
        }
    }

    // MARK: - Data sniffing

    /// Pure; callable from detached tasks without await.
    nonisolated(unsafe) static func looksLikeMP3(_ data: Data) -> Bool {
        guard data.count > 256 else { return false }
        if data.starts(with: Data([0x49, 0x44, 0x33])) { return true } // "ID3"
        let b0 = data[0], b1 = data[1]
        if b0 == 0xFF && (b1 & 0xE0) == 0xE0 { return true }          // MPEG frames
        if data.starts(with: Data([0x3C, 0x74, 0x6D, 0x6C])) { return false } // "<tml"
        if data.starts(with: Data([0x3C, 0x68, 0x74, 0x6D, 0x6C])) { return false } // "<html"
        if data.starts(with: Data([0x7B, 0x22])) { return false }     // JSON
        return false
    }
}
