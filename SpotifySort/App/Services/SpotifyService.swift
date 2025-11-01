import Foundation
import SwiftUI

/// High-level Spotify service coordinating client, cache, and auth.
/// Publishes state for UI binding.
@MainActor
final class SpotifyService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []
    
    // MARK: - Dependencies
    
    private let client: SpotifyClient
    private let cache: TrackMetadataCache
    private let auth: AuthManager
    
    // MARK: - Initialization
    
    init(client: SpotifyClient, cache: TrackMetadataCache, auth: AuthManager) {
        self.client = client
        self.cache = cache
        self.auth = auth
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
        
        let missing = await artistIDs.asyncFilter { !(await cache.hasArtistGenres(id: $0)) }
        guard !missing.isEmpty else { return }
        
        do {
            let fetched = try await client.fetchArtistGenres(artistIDs: missing, token: token)
            await cache.setArtistGenresBatch(fetched)
            await cache.save()
        } catch {
            // Fail silently for metadata
        }
    }
    
    func ensureTrackPopularity(for trackIDs: [String]) async {
        guard let token = auth.accessToken else { return }
        
        let missing = await trackIDs.asyncFilter { !(await cache.hasTrackPopularity(id: $0)) }
        guard !missing.isEmpty else { return }
        
        do {
            let fetched = try await client.fetchTrackPopularity(trackIDs: missing, token: token)
            await cache.setTrackPopularityBatch(fetched)
            await cache.save()
        } catch {
            // Fail silently for metadata
        }
    }
    
    // MARK: - Cache Access (for UI)
    
    func getArtistGenres(id: String) async -> [String]? {
        await cache.getArtistGenres(id: id)
    }
    
    func getTrackPopularity(id: String) async -> Int? {
        await cache.getTrackPopularity(id: id)
    }
    
    func getPreviewURL(key: String) async -> String? {
        await cache.getPreviewURL(key: key)
    }
    
    func setPreviewURL(key: String, url: String) async {
        await cache.setPreviewURL(key: key, url: url)
        await cache.save()
    }
}

private extension Array {
    // Helper for async filtering
    func asyncFilter(_ isIncluded: (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
        }
        return result
    }
}
