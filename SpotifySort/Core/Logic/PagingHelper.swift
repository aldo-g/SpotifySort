import Foundation

/// Pure logic for paginating large collections into smaller chunks.
/// Handles index calculations, page boundaries, and "more to load" checks.
struct PagingHelper {
    
    // MARK: - Page Calculation
    
    /// Calculate the next page range to load.
    /// Returns nil if no more items to load.
    ///
    /// - Parameters:
    ///   - currentCursor: Current position in the collection
    ///   - pageSize: Number of items per page
    ///   - totalCount: Total number of items in collection
    /// - Returns: Range to load, or nil if at end
    ///
    /// Example:
    /// ```swift
    /// let range = PagingHelper.nextPageRange(
    ///     currentCursor: 0,
    ///     pageSize: 20,
    ///     totalCount: 100
    /// )
    /// // Returns: 0..<20
    /// ```
    static func nextPageRange(
        currentCursor: Int,
        pageSize: Int,
        totalCount: Int
    ) -> Range<Int>? {
        guard currentCursor < totalCount else { return nil }
        let end = min(currentCursor + pageSize, totalCount)
        return currentCursor..<end
    }
    
    /// Check if there are more items to load.
    static func hasMore(
        currentCursor: Int,
        totalCount: Int,
        isRemoteComplete: Bool = true
    ) -> Bool {
        if !isRemoteComplete { return true }  // Still fetching from remote
        return currentCursor < totalCount
    }
    
    /// Calculate how many items remain to be loaded.
    static func remaining(
        currentCursor: Int,
        totalCount: Int
    ) -> Int {
        max(0, totalCount - currentCursor)
    }
    
    /// Check if we should preload more data (buffer threshold reached).
    /// Returns true if remaining items are below threshold.
    ///
    /// Example:
    /// ```swift
    /// // Load more when < 5 items remain in deck
    /// if PagingHelper.shouldTopUp(remaining: 3, threshold: 5) {
    ///     await loadMore()
    /// }
    /// ```
    static func shouldTopUp(
        currentPosition: Int,
        deckSize: Int,
        threshold: Int
    ) -> Bool {
        let remaining = deckSize - currentPosition
        return remaining <= threshold
    }
    
    // MARK: - Warm Start Logic
    
    /// Calculate target for warm start (initial batch loading).
    /// Ensures we have enough items before showing UI.
    static func warmStartProgress(
        currentCount: Int,
        target: Int
    ) -> (isComplete: Bool, percentage: Double) {
        let isComplete = currentCount >= target
        let percentage = min(1.0, Double(currentCount) / Double(max(target, 1)))
        return (isComplete, percentage)
    }
    
    // MARK: - Slice/Extract Helpers
    
    /// Extract a page from a collection as a new array.
    static func extractPage<T>(
        from collection: [T],
        currentCursor: Int,
        pageSize: Int
    ) -> [T] {
        guard let range = nextPageRange(
            currentCursor: currentCursor,
            pageSize: pageSize,
            totalCount: collection.count
        ) else { return [] }
        
        return Array(collection[range])
    }
    
    /// Get prefix up to cursor (for "load all up to this point" strategy).
    static func prefixUpToCursor<T>(
        from collection: [T],
        cursor: Int
    ) -> [T] {
        let end = min(cursor, collection.count)
        return Array(collection.prefix(end))
    }
    
    // MARK: - Mode-Specific Helpers
    
    /// Paging state for Liked Songs (with remote paging).
    struct LikedPagingState {
        var localCursor: Int = 0          // Position in local array
        var remoteNextURL: String? = nil  // Next remote page URL
        var isRemoteComplete: Bool = false
        
        mutating func advanceLocal(by pageSize: Int, totalLocal: Int) {
            localCursor = min(localCursor + pageSize, totalLocal)
        }
        
        mutating func markRemoteComplete() {
            isRemoteComplete = (remoteNextURL == nil)
        }
        
        func hasMore(totalLocal: Int) -> Bool {
            PagingHelper.hasMore(
                currentCursor: localCursor,
                totalCount: totalLocal,
                isRemoteComplete: isRemoteComplete
            )
        }
    }
    
    /// Paging state for Playlists (all loaded upfront).
    struct PlaylistPagingState {
        var cursor: Int = 0
        
        mutating func advance(by pageSize: Int, totalCount: Int) {
            cursor = min(cursor + pageSize, totalCount)
        }
        
        func hasMore(totalCount: Int) -> Bool {
            cursor < totalCount
        }
    }
}
