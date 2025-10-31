import Foundation

/// Batches metadata prefetch for a set of tracks (popularity + primary artist genres).
/// Intentionally lightweight so any screen can call it when the deck changes.
@MainActor
final class TrackMetadataService: ObservableObject {
    /// Fetch/populate metadata caches on SpotifyService.
    /// - Parameters:
    ///   - tracks: list of tracks currently visible / about to be used
    ///   - service: shared SpotifyService instance (coordinates with cache)
    func prefetch(for tracks: [Track], service: SpotifyService) async {
        guard !tracks.isEmpty else { return }

        // Track popularity
        let trackIDs: [String] = tracks.compactMap { $0.id }
        if !trackIDs.isEmpty {
            await service.ensureTrackPopularity(for: trackIDs)
        }

        // Primary artist genres (limit to one artist per track)
        let artistIDs: [String] = tracks.compactMap { $0.artists.first?.id }
        if !artistIDs.isEmpty {
            await service.ensureArtistGenres(for: artistIDs)
        }
    }
}
