import SwiftUI

/// ViewModel for managing deck state and orchestrating sorting operations.
/// Coordinates between UI and services, handles all business logic.
@MainActor
final class DeckViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var deck: [PlaylistTrack] = []
    @Published var topIndex: Int = 0
    @Published var isLoading = true
    @Published var duplicateIDs: Set<String> = []
    @Published var dragX: CGFloat = 0
    
    // MARK: - Dependencies
    
    private let api: SpotifyAPI
    private let auth: AuthManager
    private let mode: SortMode
    private let listKey: String
    
    // MARK: - Services
    
    private var likedService: LikedSongsService?
    private var playlistService: PlaylistService?
    
    // MARK: - Private State
    
    private var nextCursor: Int = 0
    private var reviewedSet: Set<String> = []
    private let sessionSeed = UUID().uuidString
    private let likedPageSize = 20
    private let playlistPageSize = 20
    
    // Cached value updated during load/paging
    @Published private(set) var hasMore: Bool = false
    
    // MARK: - Computed Properties
    
    var leftIntensity: CGFloat {
        max(0, min(1, (-dragX) / 120))
    }
    
    var rightIntensity: CGFloat {
        max(0, min(1, dragX / 120))
    }
    
    var isComplete: Bool {
        !isLoading && topIndex >= deck.count && !hasMore
    }
    
    var chipTitle: String {
        switch mode {
        case .liked: return "Liked Songs"
        case .playlist(let pl): return pl.name
        }
    }
    
    var currentPlaylistID: String? {
        if case .playlist(let pl) = mode { return pl.id }
        return nil
    }
    
    // MARK: - Initialization
    
    init(mode: SortMode, api: SpotifyAPI, auth: AuthManager) {
        self.mode = mode
        self.api = api
        self.auth = auth
        
        switch mode {
        case .liked:
            self.listKey = "liked"
            self.likedService = LikedSongsService(
                api: api,
                auth: auth,
                sessionSeed: sessionSeed,
                warmStartTarget: 100
            )
        case .playlist(let pl):
            self.listKey = "playlist:\(pl.id)"
            self.playlistService = PlaylistService(
                api: api,
                auth: auth,
                playlistID: pl.id
            )
        }
    }
    
    // MARK: - Public API
    
    /// Load initial deck of cards
    func load() async {
        // Load user/playlists if needed
        if api.user == nil { try? await api.loadMe(auth: auth) }
        if api.playlists.isEmpty { try? await api.loadPlaylists(auth: auth) }
        
        // Load reviewed tracks
        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)
        
        switch mode {
        case .liked:
            await loadLikedSongs()
        case .playlist:
            await loadPlaylist()
        }
        
        await updateHasMore()
        isLoading = false
    }
    
    /// Handle swipe action
    func swipe(direction: SwipeDirection, item: PlaylistTrack) async {
        dragX = 0
        
        // Mark as reviewed
        if let id = item.track?.id {
            ReviewStore.shared.addReviewed(id, for: listKey)
            reviewedSet.insert(id)
        } else if let uri = item.track?.uri {
            ReviewStore.shared.addReviewed(uri, for: listKey)
            reviewedSet.insert(uri)
        }
        
        // Remove if swiped left
        if direction == .left, let track = item.track {
            switch mode {
            case .liked:
                if let id = track.id {
                    await removeFromLiked(id: id, track: track)
                }
            case .playlist(let pl):
                if let uri = track.uri {
                    await removeFromPlaylist(plID: pl.id, uri: uri, track: track)
                }
            }
        }
        
        // Advance to next card
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Top up if needed
        await topUpIfNeeded()
    }
    
    /// Check if track is duplicate
    func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
    }
    
    /// Update drag offset (for edge glow)
    func updateDragX(_ value: CGFloat) {
        dragX = value
    }
    
    // MARK: - Private - Liked Songs
    
    private func loadLikedSongs() async {
        guard let service = likedService else { return }
        
        do {
            // Warm start
            try await service.warmStart(reviewedIDs: reviewedSet)
            
            // Load first page
            let result = await service.getPage(
                currentCursor: 0,
                pageSize: likedPageSize
            )
            deck = result.tracks
            nextCursor = result.newCursor
            
            // Continue fetching in background
            Task.detached { [weak self] in
                guard let self else { return }
                if let service = await self.likedService {
                    await service.backgroundFetchRemaining(reviewedIDs: await self.reviewedSet)
                }
                await self.topUpIfNeeded()
            }
        } catch {
            print("Liked songs load error:", error)
        }
    }
    
    // MARK: - Private - Playlist
    
    private func loadPlaylist() async {
        guard let service = playlistService else { return }
        
        do {
            // Load all tracks + detect duplicates (async, off main thread)
            try await service.load(reviewedURIs: reviewedSet)
            
            // Get duplicates
            duplicateIDs = await service.getDuplicates()
            
            // Load first page
            let result = await service.getPage(
                currentCursor: 0,
                pageSize: playlistPageSize
            )
            deck = result.tracks
            nextCursor = result.newCursor
        } catch {
            print("Playlist load error:", error)
        }
    }
    
    // MARK: - Private - Paging
    
    private func updateHasMore() async {
        let result: Bool
        switch mode {
        case .liked:
            guard let service = likedService else { result = false; return }
            result = await service.hasMore(cursor: nextCursor)
        case .playlist:
            guard let service = playlistService else { result = false; return }
            result = await service.hasMore(cursor: nextCursor)
        }
        hasMore = result
    }
    
    private func topUpIfNeeded() async {
        let shouldLoad = PagingHelper.shouldTopUp(
            currentPosition: topIndex,
            deckSize: deck.count,
            threshold: 5
        )
        guard shouldLoad else { return }
        
        switch mode {
        case .liked:
            guard let service = likedService else { return }
            let result = await service.getPage(
                currentCursor: nextCursor,
                pageSize: likedPageSize
            )
            if !result.tracks.isEmpty {
                deck = result.tracks
                nextCursor = result.newCursor
            }
            
        case .playlist:
            guard let service = playlistService else { return }
            let result = await service.getPage(
                currentCursor: nextCursor,
                pageSize: playlistPageSize
            )
            if !result.tracks.isEmpty {
                deck.append(contentsOf: result.tracks)
                nextCursor = result.newCursor
            }
        }
        
        await updateHasMore()
    }
    
    // MARK: - Private - Removal
    
    private func removeFromLiked(id: String, track: Track) async {
        do {
            try await api.batchUnsaveTracks(trackIDs: [id], auth: auth)
            let entry = RemovalEntry(
                source: .liked,
                playlistID: nil,
                playlistName: nil,
                trackID: track.id,
                trackURI: track.uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            HistoryStore.shared.add([entry])
        } catch {
            print("Unsave failed:", error)
        }
    }
    
    private func removeFromPlaylist(plID: String, uri: String, track: Track) async {
        do {
            try await api.batchRemoveTracks(playlistID: plID, uris: [uri], auth: auth)
            let entry = RemovalEntry(
                source: .playlist,
                playlistID: plID,
                playlistName: modePlaylistName,
                trackID: track.id,
                trackURI: track.uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            HistoryStore.shared.add([entry])
        } catch {
            print("Remove from playlist failed:", error)
        }
    }
    
    // MARK: - Helpers
    
    private var modePlaylistName: String? {
        if case .playlist(let pl) = mode {
            return pl.name
        }
        return nil
    }
}
