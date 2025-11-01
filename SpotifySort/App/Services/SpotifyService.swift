import Foundation
import SwiftUI

/// High-level Spotify service coordinating client, cache, and auth.
/// Publishes state for UI binding.
@MainActor
final class SpotifyService: ObservableObject {  // ← Add conformance
    
    // MARK: - Published State
    
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []
    
    // MARK: - Dependencies
    
    private let client: SpotifyClient
    private let cache: TrackMetadataCache
    private let auth: AuthManager
    private let dataProvider: SpotifyDataProvider
    
    // MARK: - Initialization
    
    init(client: SpotifyClient, cache: TrackMetadataCache, auth: AuthManager) {
        self.client = client
        self.cache = cache
        self.auth = auth
        self.dataProvider = SpotifyDataProvider(client: client, auth: auth)
    }
    
    // MARK: - User / Playlists
    
    func loadMe() async throws {
        guard let token = auth.accessToken else { return }
        user = try await client.fetchUser(token: token)
    }
    
    func loadPlaylists() async throws {
        guard let token = auth.accessToken else { return }
        playlists = try await client.fetchPlaylists(token: token)
    }
    
    // MARK: - TrackDataProvider Implementation
    
    func loadAllPlaylistTracksOrdered(
        playlistID: String,
        reviewedURIs: Set<String>
    ) async throws -> [PlaylistTrack] {
        guard let token = auth.accessToken else { return [] }
        
        let all = try await client.fetchAllPlaylistTracks(
            playlistID: playlistID,
            token: token
        )
        
        let (unreviewed, reviewed) = all.partitioned {
            guard let uri = $0.track?.uri else { return false }
            return !reviewedURIs.contains(uri)
        }
        
        return unreviewed.shuffled() + reviewed.shuffled()
    }
    
    func fetchSavedTracksPage(nextURL: String? = nil) async throws -> (items: [PlaylistTrack], next: String?) {
        guard let token = auth.accessToken else { return ([], nil) }
        return try await client.fetchSavedTracksPage(token: token, nextURL: nextURL)
    }
    
    // MARK: - Mutations
    
    func batchRemoveTracks(playlistID: String, uris: [String]) async throws {
        guard let token = auth.accessToken else { return }
        try await client.removeTracks(playlistID: playlistID, uris: uris, token: token)
    }
    
    func batchUnsaveTracks(trackIDs: [String]) async throws {
        guard let token = auth.accessToken else { return }
        try await client.unsaveTracks(trackIDs: trackIDs, token: token)
    }
    
    func batchSaveTracks(trackIDs: [String]) async throws {
        guard let token = auth.accessToken else { return }
        try await client.saveTracks(trackIDs: trackIDs, token: token)
    }
    
    func batchAddTracks(playlistID: String, uris: [String]) async throws {
        guard let token = auth.accessToken else { return }
        try await client.addTracks(playlistID: playlistID, uris: uris, token: token)
    }
    
    // MARK: - Metadata (Cached)
    
    func ensureArtistGenres(for artistIDs: [String]) async {
        guard let token = auth.accessToken else { return }
        
        let missing = artistIDs.filter { !cache.hasArtistGenres(id: $0) }
        guard !missing.isEmpty else { return }
        
        do {
            let fetched = try await client.fetchArtistGenres(artistIDs: missing, token: token)
            cache.setArtistGenresBatch(fetched)
            cache.save()
        } catch {
            // Fail silently for metadata
        }
    }
    
    func ensureTrackPopularity(for trackIDs: [String]) async {
        guard let token = auth.accessToken else { return }
        
        let missing = trackIDs.filter { !cache.hasTrackPopularity(id: $0) }
        guard !missing.isEmpty else { return }
        
        do {
            let fetched = try await client.fetchTrackPopularity(trackIDs: missing, token: token)
            cache.setTrackPopularityBatch(fetched)
            cache.save()
        } catch {
            // Fail silently for metadata
        }
    }
    
    // MARK: - Cache Access (for UI)
    
    func getArtistGenres(id: String) -> [String]? {
        cache.getArtistGenres(id: id)
    }
    
    func getTrackPopularity(id: String) -> Int? {
        cache.getTrackPopularity(id: id)
    }
    
    func getPreviewURL(key: String) -> String? {
        cache.getPreviewURL(key: key)
    }
    
    func setPreviewURL(key: String, url: String) {
        cache.setPreviewURL(key: key, url: url)
        cache.save()
    }
}

// MARK: - Helpers

private extension Array {
    func partitioned(_ isFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for el in self {
            if isFirst(el) { first.append(el) } else { second.append(el) }
        }
        return (first, second)
    }
}
