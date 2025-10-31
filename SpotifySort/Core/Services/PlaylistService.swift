import Foundation

/// Actor-based service for managing Playlist loading and state.
/// Loads all tracks upfront, detects duplicates, and provides paged access.
actor PlaylistService {
    
    // MARK: - State
    
    private var orderedAll: [PlaylistTrack] = []
    private var duplicateIDs: Set<String> = []
    private var isLoaded = false
    
    private let service: SpotifyService  // ← Changed from 'api'
    private let auth: AuthManager
    private let playlistID: String
    
    // MARK: - Initialization
    
    init(
        service: SpotifyService,
        auth: AuthManager,
        playlistID: String
    ) {
        self.service = service
        self.auth = auth
        self.playlistID = playlistID
    }
    
    // MARK: - Public API
    
    /// Load all playlist tracks and detect duplicates.
    /// This is the initial load - fetches everything from API.
    func load(reviewedURIs: Set<String>) async throws {
        guard !isLoaded else { return }
        
        // Load all tracks from service
        orderedAll = try await service.loadAllPlaylistTracksOrdered(
            playlistID: playlistID,
            reviewedURIs: reviewedURIs
        )
        
        // Detect duplicates in background (off main thread)
        duplicateIDs = await DuplicateDetector.detect(orderedAll)
        
        isLoaded = true
    }
    
    /// Get a page of tracks.
    /// Returns the requested page as a new array.
    func getPage(
        currentCursor: Int,
        pageSize: Int
    ) -> (tracks: [PlaylistTrack], newCursor: Int) {
        let page = PagingHelper.extractPage(
            from: orderedAll,
            currentCursor: currentCursor,
            pageSize: pageSize
        )
        
        let newCursor = currentCursor + page.count
        return (page, newCursor)
    }
    
    /// Check if more tracks are available.
    func hasMore(cursor: Int) -> Bool {
        PagingHelper.hasMore(
            currentCursor: cursor,
            totalCount: orderedAll.count
        )
    }
    
    /// Get duplicate track IDs.
    func getDuplicates() -> Set<String> {
        duplicateIDs
    }
    
    /// Get total count of tracks.
    func totalCount() -> Int {
        orderedAll.count
    }
    
    /// Check if track is a duplicate.
    func isDuplicate(trackID: String) -> Bool {
        duplicateIDs.contains(trackID)
    }
    
    /// Check if the playlist is loaded.
    func loaded() -> Bool {
        isLoaded
    }
    
    // MARK: - Advanced (Future Use)
    
    /// Re-sort tracks (useful if reviewed state changes).
    func resort(reviewedURIs: Set<String>, sessionSeed: String) {
        orderedAll = DeckRanker.sort(
            orderedAll,
            reviewedIDs: reviewedURIs,
            sessionSeed: sessionSeed
        )
    }
    
    /// Add a track (for future undo/redo features).
    func addTrack(_ track: PlaylistTrack) {
        orderedAll.append(track)
    }
    
    /// Remove a track (for future undo/redo features).
    func removeTrack(uri: String) {
        orderedAll.removeAll { $0.track?.uri == uri }
    }
}
