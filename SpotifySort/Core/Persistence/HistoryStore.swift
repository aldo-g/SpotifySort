import Foundation
import SwiftUI
import Combine

/// UI-facing history store with published state and background persistence.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    
    @Published private(set) var entries: [RemovalEntry] = []
    
    private let persister = HistoryPersister()
    private let maxEntries = 500
    private var backgroundTaskID: UIBackgroundTaskIdentifier?
    
    private init() {
        Task {
            entries = await persister.load()
        }
        setupBackgroundNotifications()
    }
    
    func add(_ newEntries: [RemovalEntry]) {
        guard !newEntries.isEmpty else { return }
        var merged = newEntries + entries
        if merged.count > maxEntries {
            merged = Array(merged.prefix(maxEntries))
        }
        entries = merged
        Task { await persister.scheduleWrite(entries) }
    }
    
    func clear() {
        entries.removeAll()
        Task { await persister.flush() }
    }
    
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        Task { await persister.scheduleWrite(entries) }
    }
    
    func removeBatch(ids: [UUID]) {
        let set = Set(ids)
        entries.removeAll { set.contains($0.id) }
        Task { await persister.scheduleWrite(entries) }
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
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        Task { [weak self] in
            guard let self else { return }
            await self.persister.flush()
            await MainActor.run { self.endBackgroundTask() }
        }
    }
    
    private func endBackgroundTask() {
        if let taskID = backgroundTaskID {
            UIApplication.shared.endBackgroundTask(taskID)
            backgroundTaskID = .invalid
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
