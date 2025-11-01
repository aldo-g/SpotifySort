// SpotifySort/Core/Services/PreviewResolver.swift

import Foundation
import Combine

/// Centralizes preview-URL resolution + waveform caching for a Track.
/// UI should not talk to Deezer/Spotify caches directly.
// MODIFIED: Changed to an actor, removed @MainActor and ObservableObject
actor PreviewResolver {
    private let service: SpotifyService
    private let cache: TrackMetadataCache

    init(service: SpotifyService, cache: TrackMetadataCache) {
        self.service = service
        self.cache = cache
    }

    /// Stable key for preview/waveform caches.
    // ADDED: nonisolated to allow calling from anywhere synchronously
    nonisolated func key(for track: Track) -> String {
        track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
    }

    /// Resolve a playable preview URL and (optionally) a precomputed waveform.
    /// The actor enforces thread safety on all internal data and async calls.
    func resolve(for track: Track) async -> (String?, [Float]?) {
        let k = key(for: track)

        // 1) Spotify-provided preview wins if present.
        if let direct = track.preview_url {
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: direct)
            return (direct, wf)
        }

        // 2) Check cache
        if let cached = await cache.getPreviewURL(key: k),
           let ok = await DeezerPreviewService.shared.validatePreview(urlString: cached, trackKey: k, track: track) {
            await cache.setPreviewURL(key: k, url: ok)
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: ok)
            return (ok, wf)
        }

        // 3) Fresh Deezer lookup.
        if let deezer = await DeezerPreviewService.shared.resolvePreview(for: track) {
            await cache.setPreviewURL(key: k, url: deezer)
            await cache.save()
            let wf = await WaveformStore.shared.waveform(for: k, previewURL: deezer)
            return (deezer, wf)
        }

        return (nil, nil)
    }
}
