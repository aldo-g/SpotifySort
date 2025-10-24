import AVFoundation

final class PreviewPlayer {
    static let shared = PreviewPlayer()
    private var player: AVPlayer?

    func play(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if let player = player, player.timeControlStatus == .playing {
            player.pause()
            return
        }
        player = AVPlayer(url: url)
        player?.play()
    }

    func stop() {
        player?.pause()
    }
}
