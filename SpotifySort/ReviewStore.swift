import Foundation

/// Very small persistence helper backed by UserDefaults.
/// We store string IDs per list key:
///  - playlists: use "playlist:<playlistID>" and store track *URIs*
///  - liked:     use "liked" and store track *IDs*
final class ReviewStore {
    static let shared = ReviewStore()
    private let defaults = UserDefaults.standard

    private func key(for listKey: String) -> String { "reviewed.\(listKey)" }

    func loadReviewed(for listKey: String) -> Set<String> {
        let k = key(for: listKey)
        let arr = defaults.array(forKey: k) as? [String] ?? []
        return Set(arr)
    }

    func addReviewed(_ id: String, for listKey: String) {
        let k = key(for: listKey)
        var set = loadReviewed(for: listKey)
        if set.insert(id).inserted {
            defaults.set(Array(set), forKey: k)
        }
    }

    func addReviewedBatch(_ ids: [String], for listKey: String) {
        guard !ids.isEmpty else { return }
        let k = key(for: listKey)
        var set = loadReviewed(for: listKey)
        for id in ids { set.insert(id) }
        defaults.set(Array(set), forKey: k)
    }
}
