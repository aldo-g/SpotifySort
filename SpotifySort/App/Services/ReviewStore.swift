import Foundation
import UIKit

/// UI-facing review store with background persistence.
final class ReviewStore {
    static let shared = ReviewStore()
    
    private let persister = ReviewPersister()
    
    private init() {
        setupBackgroundNotifications()
    }
    
    func loadReviewed(for listKey: String) -> Set<String> {
        let key = "reviewed.\(listKey)"
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(arr)
    }
    
    func addReviewed(_ id: String, for listKey: String) {
        var set = loadReviewed(for: listKey)
        guard set.insert(id).inserted else { return }
        
        // Capture immutable copy for Task
        let updatedSet = set
        Task { await persister.scheduleWrite(updatedSet, for: listKey) }
    }
    
    func addReviewedBatch(_ ids: [String], for listKey: String) {
        guard !ids.isEmpty else { return }
        var set = loadReviewed(for: listKey)
        for id in ids { set.insert(id) }
        
        // Capture immutable copy for Task
        let updatedSet = set
        Task { await persister.scheduleWrite(updatedSet, for: listKey) }
    }
    
    // MARK: - Background Safety
    
    private func setupBackgroundNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appWillResignActive() {
        Task { await persister.flush() }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
