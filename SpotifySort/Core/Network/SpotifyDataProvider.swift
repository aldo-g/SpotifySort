import Foundation

/// Non-@MainActor data provider for Core services.
/// Keeps background threads on background threads.
final class SpotifyDataProvider: TrackDataProvider {
    
    let client: SpotifyClient  // ← Remove 'private'
    let auth: AuthManager      // ← Remove 'private'
    
    init(client: SpotifyClient, auth: AuthManager) {
        self.client = client
        self.auth = auth
    }
    
    // MARK: - TrackDataProvider
    
    func fetchSavedTracksPage(nextURL: String? = nil) async throws -> (items: [PlaylistTrack], next: String?) {
        guard let token = await auth.getAccessToken() else { return ([], nil) }
        return try await client.fetchSavedTracksPage(token: token, nextURL: nextURL)
    }
    
    func loadAllPlaylistTracksOrdered(
        playlistID: String,
        reviewedURIs: Set<String>
    ) async throws -> [PlaylistTrack] {
        guard let token = await auth.getAccessToken() else { return [] }
        
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
