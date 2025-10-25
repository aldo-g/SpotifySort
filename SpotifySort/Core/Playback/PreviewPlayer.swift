import AVFoundation
import Combine

@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    // 20-band simplified “sound profile”
    @Published var levels: [Float] = Array(repeating: 0, count: 20)

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var currentTask: Task<Void, Never>?

    // MARK: - Play / Stop

    func play(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        stop()

        currentTask = Task.detached {
            do {
                // Configure audio session for playback
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)

                // Download preview to temp file
                let (data, _) = try await URLSession.shared.data(from: url)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview.mp3")
                try data.write(to: tmp)

                let file = try AVAudioFile(forReading: tmp)
                await MainActor.run { self.startEngine(with: file) }
            } catch {
                print("Preview load error:", error)
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch { print("Failed to deactivate AVAudioSession:", error) }
    }

    // MARK: - Engine setup

    private func startEngine(with file: AVAudioFile) {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        // Tap for amplitude analysis
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: file.processingFormat) { [weak self] buf, _ in
            self?.processBuffer(buf)
        }

        do {
            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()
            print("✅ Preview playing through device audio")
        } catch {
            print("Audio engine start failed:", error)
        }
    }

    // MARK: - Amplitude processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let sliceSize = max(frameLength / levels.count, 1)
        var newLevels: [Float] = []
        newLevels.reserveCapacity(levels.count)

        for i in stride(from: 0, to: frameLength, by: sliceSize) {
            let sliceCount = min(sliceSize, frameLength - i)
            var sum: Float = 0
            for j in 0..<sliceCount {
                let sample = channelData[i + j]
                sum += sample * sample
            }
            let meanSquare = sum / Float(sliceCount)
            let rms = sqrt(meanSquare)
            newLevels.append(rms)
        }

        DispatchQueue.main.async {
            self.levels = newLevels
        }
    }
}
