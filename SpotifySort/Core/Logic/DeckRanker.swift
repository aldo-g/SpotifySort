import Foundation

/// Pure logic for ranking and sorting tracks in the deck.
/// Handles session-stable randomization with reviewed tracks deprioritized.
struct DeckRanker {
    
    // MARK: - Public API
    
    /// Sort tracks: unreviewed first (shuffled), then reviewed (shuffled).
    /// Uses a session seed for stable ordering within a session.
    static func sort(
        _ tracks: [PlaylistTrack],
        reviewedIDs: Set<String>,
        sessionSeed: String
    ) -> [PlaylistTrack] {
        tracks.sorted { a, b in
            let keyA = rankKey(for: a, reviewedIDs: reviewedIDs, sessionSeed: sessionSeed)
            let keyB = rankKey(for: b, reviewedIDs: reviewedIDs, sessionSeed: sessionSeed)
            return keyA < keyB
        }
    }
    
    /// Generate a stable rank key: (reviewed: 0 or 1, hash: UInt64)
    /// - Reviewed tracks get 1, unreviewed get 0 (unreviewed sort first)
    /// - Hash provides deterministic shuffling per session
    static func rankKey(
        for item: PlaylistTrack,
        reviewedIDs: Set<String>,
        sessionSeed: String
    ) -> (Int, UInt64) {
        let reviewed = isReviewed(item, in: reviewedIDs) ? 1 : 0
        let id = item.track?.id ?? item.track?.uri ?? UUID().uuidString
        let hash = fnv1a64(sessionSeed + "|" + id)
        return (reviewed, hash)
    }
    
    /// Check if a track has been reviewed (by ID or URI)
    static func isReviewed(_ item: PlaylistTrack, in reviewedSet: Set<String>) -> Bool {
        if let id = item.track?.id, reviewedSet.contains(id) { return true }
        if let uri = item.track?.uri, reviewedSet.contains(uri) { return true }
        return false
    }
    
    /// Partition tracks into (unreviewed, reviewed) arrays.
    /// Useful for manual shuffling if needed.
    static func partition(
        _ tracks: [PlaylistTrack],
        reviewedIDs: Set<String>
    ) -> (unreviewed: [PlaylistTrack], reviewed: [PlaylistTrack]) {
        var unreviewed: [PlaylistTrack] = []
        var reviewed: [PlaylistTrack] = []
        
        for track in tracks {
            if isReviewed(track, in: reviewedIDs) {
                reviewed.append(track)
            } else {
                unreviewed.append(track)
            }
        }
        
        return (unreviewed, reviewed)
    }
    
    // MARK: - Hash Function (FNV-1a 64-bit)
    
    /// Fast, non-cryptographic hash for deterministic shuffling.
    /// Same input always produces same output (critical for session stability).
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        
        return hash
    }
}
