import Foundation
import Combine

/// Centralizes preview-URL resolution + waveform caching for a Track.
/// UI should not talk to Deezer/Spotify caches directly.
@MainActor
final class PreviewResolver: ObservableObject {
    private let service: SpotifyService
    private let cache: TrackMetadataCache

    init(service: SpotifyService, cache: TrackMetadataCache) {
        self.service = service
        self.cache = cache
    }

    /// Stable key for preview/waveform caches.
    func key(for track: Track) -> String {
        track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
    }

    /// Resolve a playable preview URL and (optionally) a precomputed waveform.
    /// Returns (url, waveform) where waveform may be nil if not yet ready.
    func resolve(for track: Track) async -> (String?, [Float]?) {
        let k = key(for: track)

        // 1) Spotify-provided preview wins if present.
        if let direct = track.preview_url {
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: direct)
            return (direct, wf)
        }

        // 2) Check cache
        if let cached = cache.getPreviewURL(key: k),
           let ok = await DeezerPreviewService.shared.validatePreview(urlString: cached, trackKey: k, track: track) {
            cache.setPreviewURL(key: k, url: ok)
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: ok)
            return (ok, wf)
        }

        // 3) Fresh Deezer lookup.
        if let deezer = await DeezerPreviewService.shared.resolvePreview(for: track) {
            cache.setPreviewURL(key: k, url: deezer)
            cache.save()
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: deezer)
            return (deezer, wf)
        }

        return (nil, nil)
    }
}
