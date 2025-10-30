import Foundation

/// Actor-based service for managing Liked Songs paging and state.
/// Runs off the main thread, handles incremental fetching with warm-start optimization.
actor LikedSongsService {
    
    // MARK: - State
    
    private var orderedAll: [PlaylistTrack] = []
    private var nextURL: String? = nil
    private var isFetching = false
    private var isComplete = false
    
    private let api: SpotifyAPI
    private let auth: AuthManager
    private let sessionSeed: String
    private let warmStartTarget: Int
    
    // MARK: - Initialization
    
    init(
        api: SpotifyAPI,
        auth: AuthManager,
        sessionSeed: String,
        warmStartTarget: Int = 100
    ) {
        self.api = api
        self.auth = auth
        self.sessionSeed = sessionSeed
        self.warmStartTarget = warmStartTarget
    }
    
    // MARK: - Public API
    
    /// Perform initial warm-start load.
    /// Fetches enough tracks to fill the deck before showing UI.
    func warmStart(reviewedIDs: Set<String>) async throws {
        while orderedAll.count < warmStartTarget && !isComplete {
            try await fetchNextPage(reviewedIDs: reviewedIDs)
        }
    }
    
    /// Continue fetching in the background after warm start.
    func backgroundFetchRemaining(reviewedIDs: Set<String>) async {
        while !isComplete {
            try? await fetchNextPage(reviewedIDs: reviewedIDs)
            // Small delay to avoid hammering the API
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }
    
    /// Get a page of tracks starting from cursor.
    /// Returns tracks and new cursor position.
    func getPage(
        currentCursor: Int,
        pageSize: Int
    ) -> (tracks: [PlaylistTrack], newCursor: Int) {
        guard let range = PagingHelper.nextPageRange(
            currentCursor: currentCursor,
            pageSize: pageSize,
            totalCount: orderedAll.count
        ) else {
            return ([], currentCursor)
        }
        
        let tracks = Array(orderedAll.prefix(range.upperBound))
        return (tracks, range.upperBound)
    }
    
    /// Get all tracks up to cursor (for "deck = prefix" strategy).
    func getAllUpTo(cursor: Int) -> [PlaylistTrack] {
        PagingHelper.prefixUpToCursor(from: orderedAll, cursor: cursor)
    }
    
    /// Check if more tracks are available (locally or remotely).
    func hasMore(cursor: Int) -> Bool {
        PagingHelper.hasMore(
            currentCursor: cursor,
            totalCount: orderedAll.count,
            isRemoteComplete: isComplete
        )
    }
    
    /// Get current total count.
    func totalCount() -> Int {
        orderedAll.count
    }
    
    /// Check if remote fetching is complete.
    func fetchComplete() -> Bool {
        isComplete
    }
    
    // MARK: - Private
    
    private func fetchNextPage(reviewedIDs: Set<String>) async throws {
        guard !isFetching, !isComplete else { return }
        
        isFetching = true
        defer { isFetching = false }
        
        // Fetch from API
        let result = try await api.fetchSavedTracksPage(auth: auth, nextURL: nextURL)
        nextURL = result.next
        
        if result.items.isEmpty {
            isComplete = (nextURL == nil)
            return
        }
        
        // Append and re-sort using DeckRanker
        orderedAll.append(contentsOf: result.items)
        orderedAll = DeckRanker.sort(
            orderedAll,
            reviewedIDs: reviewedIDs,
            sessionSeed: sessionSeed
        )
        
        if nextURL == nil {
            isComplete = true
        }
    }
}
