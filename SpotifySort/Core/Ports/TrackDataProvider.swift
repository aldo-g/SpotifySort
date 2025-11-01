import Foundation

/// Port defining track data operations needed by Core services.
/// Implemented by app-layer data providers.
protocol TrackDataProvider: Sendable {  // ← Remove 'public'
    func fetchSavedTracksPage(nextURL: String?) async throws -> (items: [PlaylistTrack], next: String?)
    
    func loadAllPlaylistTracksOrdered(
        playlistID: String,
        reviewedURIs: Set<String>
    ) async throws -> [PlaylistTrack]
}
