// SpotifySort/Core/Persistence/ReviewStore.swift

import Foundation
// import UIKit <-- Removed since no UI/App logic remains

/// Thread-safe actor managing reviewed track IDs via background persistence.
actor ReviewStore {
    static let shared = ReviewStore()
    
    private let persister = ReviewPersister()
    
    // Private init to enforce singleton pattern on the actor
    private init() {}
    
    // All access must now be asynchronous (await)
    func loadReviewed(for listKey: String) async -> Set<String> {
        // Delegates synchronous UserDefaults access to the persister actor
        await persister.load(for: listKey)
    }
    
    func addReviewed(_ id: String, for listKey: String) async {
        // Awaits load, mutates state, then schedules the write
        var set = await loadReviewed(for: listKey)
        guard set.insert(id).inserted else { return }
        await persister.scheduleWrite(set, for: listKey)
    }
    
    func addReviewedBatch(_ ids: [String], for listKey: String) async {
        guard !ids.isEmpty else { return }
        var set = await loadReviewed(for: listKey)
        for id in ids { set.insert(id) }
        await persister.scheduleWrite(set, for: listKey)
    }
    
    func flush() async {
        await persister.flush()
    }
    
    // Removed all UIApplication/NotificationCenter setup (this is a Core concern)
}
