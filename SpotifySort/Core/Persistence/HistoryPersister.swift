import Foundation

/// Actor handling background disk I/O for history entries.
/// Debounces rapid writes for performance, flushes on demand for safety.
actor HistoryPersister {
    private var pendingEntries: [RemovalEntry] = []
    private var saveTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let key = "history.removals.v1"
    
    func scheduleWrite(_ entries: [RemovalEntry]) {
        pendingEntries = entries
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            writeToDisk()  // ← Remove await (sync function)
        }
    }
    
    func flush() {
        saveTask?.cancel()
        writeToDisk()  // ← Remove await (sync function)
    }
    
    func load() -> [RemovalEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RemovalEntry].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private func writeToDisk() {
        guard !pendingEntries.isEmpty else { return }
        if let data = try? encoder.encode(pendingEntries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
