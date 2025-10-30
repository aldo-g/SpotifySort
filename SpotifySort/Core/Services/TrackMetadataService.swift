import Foundation

/// Batches metadata prefetch for a set of tracks (popularity + primary artist genres).
/// Intentionally lightweight so any screen can call it when the deck changes.
@MainActor
final class TrackMetadataService: ObservableObject {
    /// Fetch/populate metadata caches on SpotifyAPI.
    /// - Parameters:
    ///   - tracks: list of tracks currently visible / about to be used
    ///   - api: shared SpotifyAPI instance (cache owner)
    ///   - auth: auth manager (for tokens)
    func prefetch(for tracks: [Track], api: SpotifyAPI, auth: AuthManager) async {
        guard !tracks.isEmpty else { return }

        // Track popularity
        let trackIDs: [String] = tracks.compactMap { $0.id }
        if !trackIDs.isEmpty {
            await api.ensureTrackPopularity(for: trackIDs, auth: auth)
        }

        // Primary artist genres (limit to one artist per track)
        let artistIDs: [String] = tracks.compactMap { $0.artists.first?.id }
        if !artistIDs.isEmpty {
            await api.ensureArtistGenres(for: artistIDs, auth: auth)
        }
    }
}
