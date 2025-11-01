// SpotifySort/App/HistoryCoordinator.swift

import SwiftUI
import Combine
import UIKit // This import is now correctly isolated in the App layer

/// App-layer coordinator managing History state publication and background persistence.
/// Moves UIKit background logic out of Core, maintaining the A+ boundary.
@MainActor
final class HistoryCoordinator: ObservableObject {
    
    // MARK: - Published State (for UI binding)
    @Published private(set) var entries: [RemovalEntry] = []
    
    // MARK: - Dependencies
    private let store: HistoryStore // The pure Core actor
    private var backgroundTaskID: UIBackgroundTaskIdentifier?
    
    init(store: HistoryStore) {
        self.store = store
        
        // Load on init and setup background saving
        Task {
            await store.load()
            self.entries = await store.getEntries()
            self.setupBackgroundNotifications()
        }
    }
    
    // MARK: - Public API (Delegates to Core)
    
    func add(_ newEntries: [RemovalEntry]) {
        Task {
            await store.add(newEntries)
            self.entries = await store.getEntries() // Re-fetch state after mutation
        }
    }
    
    func clear() {
        Task {
            await store.clear()
            self.entries = await store.getEntries()
        }
    }
    
    func remove(id: UUID) {
        Task {
            await store.remove(id: id)
            self.entries = await store.getEntries()
        }
    }
    
    // MARK: - Background Safety (UIKit dependency)
    
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
        
        // Flush Core actor on a background thread
        Task { [weak self] in
            guard let self else { return }
            await self.store.flush()
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
