// SpotifySort/Core/Persistence/HistoryStore.swift

import Foundation
import Combine // Still need Combine for Task.detached compatibility, but removed published

/// Thread-safe actor managing history entries via background persistence.
/// This is a pure Core component with no knowledge of UI/UIApplication.
actor HistoryStore {
    
    // Static shared instance is acceptable for a Core singleton managed by AppEnvironment
    static let shared = HistoryStore()
    
    private var internalEntries: [RemovalEntry] = [] // Internal state is not @Published
    private let persister = HistoryPersister()
    private let maxEntries = 500
    
    private init() {
        // Init logic moved to load()
    }
    
    // MARK: - Public Actor API (async/await access only)
    
    func load() async {
        internalEntries = await persister.load()
    }
    
    func getEntries() async -> [RemovalEntry] {
        internalEntries
    }
    
    func add(_ newEntries: [RemovalEntry]) async {
        guard !newEntries.isEmpty else { return }
        var merged = newEntries + internalEntries
        if merged.count > maxEntries {
            merged = Array(merged.prefix(maxEntries))
        }
        internalEntries = merged
        await persister.scheduleWrite(internalEntries)
    }
    
    func clear() async {
        internalEntries.removeAll()
        await persister.flush()
    }
    
    func remove(id: UUID) async {
        internalEntries.removeAll { $0.id == id }
        await persister.scheduleWrite(internalEntries)
    }
    
    func removeBatch(ids: [UUID]) async {
        let set = Set(ids)
        internalEntries.removeAll { set.contains($0.id) }
        await persister.scheduleWrite(internalEntries)
    }
    
    func flush() async {
        await persister.flush()
    }
}
