import Foundation

/// Pure logic for detecting duplicate tracks in a collection.
/// Runs asynchronously to avoid blocking the main thread.
struct DuplicateDetector {
    
    // MARK: - Public API
    
    /// Detect tracks that appear multiple times in the collection.
    /// Returns a Set of track IDs that have duplicates.
    ///
    /// - Parameter tracks: Collection of tracks to analyze
    /// - Returns: Set of track IDs that appear more than once
    ///
    /// Example:
    /// ```swift
    /// let dupes = await DuplicateDetector.detect(tracks)
    /// if dupes.contains(trackID) { /* show badge */ }
    /// ```
    static func detect(_ tracks: [PlaylistTrack]) async -> Set<String> {
        // Run off main thread for large collections
        await Task.detached {
            var counts: [String: Int] = [:]
            counts.reserveCapacity(tracks.count)
            
            // Count occurrences of each track ID
            for item in tracks {
                guard let id = item.track?.id else { continue }
                counts[id, default: 0] += 1
            }
            
            // Return IDs that appear more than once
            let duplicates = counts.filter { $0.value > 1 }.map { $0.key }
            return Set(duplicates)
        }.value
    }
    
    /// Synchronous version for small collections (< 100 items).
    /// Use the async version for larger collections to avoid blocking.
    static func detectSync(_ tracks: [PlaylistTrack]) -> Set<String> {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(tracks.count)
        
        for item in tracks {
            guard let id = item.track?.id else { continue }
            counts[id, default: 0] += 1
        }
        
        let duplicates = counts.filter { $0.value > 1 }.map { $0.key }
        return Set(duplicates)
    }
    
    /// Check if a specific track ID is a duplicate in the collection.
    /// More efficient than detecting all if you only need to check one.
    static func isDuplicate(trackID: String, in tracks: [PlaylistTrack]) -> Bool {
        var count = 0
        for item in tracks {
            if item.track?.id == trackID {
                count += 1
                if count > 1 { return true }
            }
        }
        return false
    }
    
    /// Group tracks by their ID, useful for showing all instances of a duplicate.
    /// Returns a dictionary: trackID -> [indices where it appears]
    static func groupDuplicates(_ tracks: [PlaylistTrack]) async -> [String: [Int]] {
        await Task.detached {
            var groups: [String: [Int]] = [:]
            
            for (index, item) in tracks.enumerated() {
                guard let id = item.track?.id else { continue }
                groups[id, default: []].append(index)
            }
            
            // Filter to only duplicates (appears more than once)
            return groups.filter { $0.value.count > 1 }
        }.value
    }
}
