import Foundation

/// Actor handling background disk I/O for reviewed track IDs.
/// Debounces rapid writes for performance, flushes on demand for safety.
actor ReviewPersister {
    private var pendingSets: [String: Set<String>] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private let defaults = UserDefaults.standard
    
    func scheduleWrite(_ set: Set<String>, for listKey: String) {
        pendingSets[listKey] = set
        saveTasks[listKey]?.cancel()
        saveTasks[listKey] = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            writeToDisk(for: listKey)
        }
    }
    
    func flush() async {
        for task in saveTasks.values { task.cancel() }
        for (listKey, _) in pendingSets {
            writeToDisk(for: listKey)
        }
    }
    
    func load(for listKey: String) -> Set<String> {
        let key = "reviewed.\(listKey)"
        let arr = defaults.array(forKey: key) as? [String] ?? []
        return Set(arr)
    }
    
    private func writeToDisk(for listKey: String) {
        guard let set = pendingSets[listKey] else { return }
        let key = "reviewed.\(listKey)"
        defaults.set(Array(set), forKey: key)
    }
}
