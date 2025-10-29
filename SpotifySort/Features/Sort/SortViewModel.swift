import SwiftUI
import Combine

/// ViewModel managing the sorting/swiping logic and state
@MainActor
final class SortViewModel: ObservableObject {
    // MARK: - Published State
    @Published private(set) var orderedAll: [PlaylistTrack] = []
    @Published private(set) var deck: [PlaylistTrack] = []
    @Published private(set) var nextCursor: Int = 0
    @Published private(set) var topIndex: Int = 0
    @Published private(set) var isLoading = true
    @Published private(set) var reviewedSet: Set<String> = []
    @Published private(set) var duplicateIDs: Set<String> = []
    @Published var dragX: CGFloat = 0
    
    // MARK: - Paging State (Liked only)
    @Published private(set) var nextURL: String? = nil
    @Published private(set) var isFetching = false
    @Published private(set) var allDone = false
    
    // MARK: - Dependencies
    private let mode: SortMode
    private let api: SpotifyAPI
    private let auth: AuthManager
    private let reviewStore: ReviewStore
    private let historyStore: HistoryStore
    
    // MARK: - Configuration
    private let sessionSeed = UUID().uuidString
    
    // MARK: - Computed Properties
    var listKey: String {
        switch mode {
        case .liked: return "liked"
        case .playlist(let pl): return "playlist:\(pl.id)"
        }
    }
    
    var moreToLoad: Bool {
        switch mode {
        case .liked:
            return !allDone || nextCursor < orderedAll.count
        case .playlist:
            return nextCursor < orderedAll.count
        }
    }
    
    var isComplete: Bool {
        !isLoading && topIndex >= deck.count && !moreToLoad
    }
    
    var currentTrack: PlaylistTrack? {
        guard topIndex < deck.count else { return nil }
        return deck[topIndex]
    }
    
    // MARK: - Initialization
    
    init(
        mode: SortMode,
        api: SpotifyAPI,
        auth: AuthManager,
        reviewStore: ReviewStore = .shared,
        historyStore: HistoryStore = .shared
    ) {
        self.mode = mode
        self.api = api
        self.auth = auth
        self.reviewStore = reviewStore
        self.historyStore = historyStore
    }
    
    // MARK: - Public Methods
    
    func load() async {
        // Ensure user and playlists are loaded
        if api.user == nil {
            try? await api.loadMe(auth: auth)
        }
        if api.playlists.isEmpty {
            try? await api.loadPlaylists(auth: auth)
        }
        
        reviewedSet = reviewStore.loadReviewed(for: listKey)
        
        switch mode {
        case .liked:
            await loadLikedTracks()
        case .playlist(let playlist):
            await loadPlaylistTracks(playlist)
        }
        
        isLoading = false
    }
    
    func handleSwipe(direction: SwipeDirection, item: PlaylistTrack) async {
        dragX = 0
        
        // Mark as reviewed
        markAsReviewed(item)
        
        // Handle removal if swiped left
        if direction == .left {
            await removeTrack(item)
        }
        
        // Advance to next card
        topIndex += 1
        
        // Trigger haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Top up deck if needed
        await topUpIfNeeded()
    }
    
    func topUpIfNeeded(force: Bool = false) async {
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }
        
        switch mode {
        case .liked:
            try? await loadNextPageLiked()
        case .playlist:
            try? await loadNextPagePlaylist()
        }
    }
    
    // MARK: - Private Methods - Loading
    
    private func loadLikedTracks() async {
        // Warm-start: fetch initial batch
        while orderedAll.count < AppConfiguration.likedWarmStartTarget, !allDone {
            await fetchNextPageAndMergeLiked()
        }
        
        nextCursor = 0
        deck.removeAll()
        try? await loadNextPageLiked()
        
        // Background fetch remaining
        Task.detached { [weak self] in
            await self?.backgroundFetchRemainingLiked()
        }
    }
    
    private func loadPlaylistTracks(_ playlist: Playlist) async {
        do {
            orderedAll = try await api.loadAllPlaylistTracksOrdered(
                playlistID: playlist.id,
                auth: auth,
                reviewedURIs: reviewedSet
            )
            recomputeDuplicates()
            deck.removeAll()
            nextCursor = 0
            try? await loadNextPagePlaylist()
        } catch {
            print("Failed to load playlist tracks:", error)
        }
    }
    
    private func backgroundFetchRemainingLiked() async {
        while !allDone {
            await fetchNextPageAndMergeLiked()
            await topUpIfNeeded()
        }
    }
    
    private func fetchNextPageAndMergeLiked() async {
        guard !isFetching, !allDone else { return }
        isFetching = true
        defer { isFetching = false }
        
        do {
            let result = try await api.fetchSavedTracksPage(auth: auth, nextURL: nextURL)
            nextURL = result.next
            
            if result.items.isEmpty {
                allDone = (nextURL == nil)
                return
            }
            
            orderedAll.append(contentsOf: result.items)
            orderedAll.sort { a, b in rankKey(a) < rankKey(b) }
            
            if nextURL == nil {
                allDone = true
            }
        } catch {
            allDone = true
            print("SavedTracks paging error: \(error)")
        }
    }
    
    private func loadNextPageLiked() async throws {
        let end = min(nextCursor + AppConfiguration.likedSortPageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck = Array(orderedAll.prefix(end))
        nextCursor = end
    }
    
    private func loadNextPagePlaylist() async throws {
        let end = min(nextCursor + AppConfiguration.playlistSortPageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck.append(contentsOf: orderedAll[nextCursor..<end])
        nextCursor = end
    }
    
    // MARK: - Private Methods - Ranking
    
    private func rankKey(_ item: PlaylistTrack) -> (Int, UInt64) {
        let reviewed = isReviewed(item) ? 1 : 0
        let id = item.track?.id ?? item.track?.uri ?? UUID().uuidString
        return (reviewed, fnv1a64(sessionSeed + "|" + id))
    }
    
    private func isReviewed(_ item: PlaylistTrack) -> Bool {
        if let id = item.track?.id { return reviewedSet.contains(id) }
        if let uri = item.track?.uri { return reviewedSet.contains(uri) }
        return false
    }
    
    private func recomputeDuplicates() {
        var counts: [String: Int] = [:]
        for item in orderedAll {
            if let id = item.track?.id {
                counts[id, default: 0] += 1
            }
        }
        duplicateIDs = Set(counts.filter { $0.value > 1 }.map { $0.key })
    }
    
    func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
    }
    
    // MARK: - Private Methods - Actions
    
    private func markAsReviewed(_ item: PlaylistTrack) {
        switch mode {
        case .liked:
            if let id = item.track?.id {
                reviewStore.addReviewed(id, for: listKey)
                reviewedSet.insert(id)
            } else if let uri = item.track?.uri {
                reviewStore.addReviewed(uri, for: listKey)
            }
            
        case .playlist:
            if let uri = item.track?.uri {
                reviewStore.addReviewed(uri, for: listKey)
                reviewedSet.insert(uri)
            }
        }
    }
    
    private func removeTrack(_ item: PlaylistTrack) async {
        guard let track = item.track else { return }
        
        switch mode {
        case .liked:
            await removeFromLiked(trackID: track.id, track: track)
            
        case .playlist(let playlist):
            await removeFromPlaylist(
                playlistID: playlist.id,
                playlistName: playlist.name,
                uri: track.uri,
                track: track
            )
        }
    }
    
    private func removeFromLiked(trackID: String?, track: Track) async {
        guard let id = trackID else { return }
        
        do {
            try await api.batchUnsaveTracks(trackIDs: [id], auth: auth)
            
            let entry = RemovalEntry(
                source: .liked,
                playlistID: nil,
                playlistName: nil,
                trackID: id,
                trackURI: track.uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            
            historyStore.add([entry])
        } catch {
            print("Unsave failed:", error)
        }
    }
    
    private func removeFromPlaylist(
        playlistID: String,
        playlistName: String,
        uri: String?,
        track: Track
    ) async {
        guard let uri = uri else { return }
        
        do {
            try await api.batchRemoveTracks(playlistID: playlistID, uris: [uri], auth: auth)
            
            let entry = RemovalEntry(
                source: .playlist,
                playlistID: playlistID,
                playlistName: playlistName,
                trackID: track.id,
                trackURI: uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            
            historyStore.add([entry])
        } catch {
            print("Remove from playlist failed:", error)
        }
    }
}

// MARK: - Hash Helper

private func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash &*= prime
    }
    return hash
}
