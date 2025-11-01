import SwiftUI
import Foundation

/// ViewModel for managing deck state and orchestrating sorting operations.
/// Coordinates between UI and services, handles all business logic.
@MainActor
final class DeckViewModel: ObservableObject {
    
    // MARK: - Published State
    // ... (rest of published properties remain unchanged)
    
    @Published var deck: [PlaylistTrack] = []
    @Published var topIndex: Int = 0
    @Published var isLoading = true
    @Published var duplicateIDs: Set<String> = []
    @Published var dragX: CGFloat = 0
    @Published private(set) var hasMore: Bool = false
    
    // Edge glow intensities via SwipeDynamics
    @Published var leftIntensity: CGFloat = 0
    @Published var rightIntensity: CGFloat = 0
    
    // MARK: - Dependencies
    
    private let service: SpotifyService  // ← Changed from 'api'
    private let auth: AuthManager
    private let history: HistoryCoordinator // NEW DEPENDENCY
    private let mode: SortMode
    private let dataProvider: any TrackDataProvider
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
    
    // MARK: - Computed Properties
    
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
    
    init(mode: SortMode, service: SpotifyService, auth: AuthManager, dataProvider: any TrackDataProvider, history: HistoryCoordinator) { // <-- MODIFIED
            self.mode = mode
            self.service = service
            self.auth = auth
            self.dataProvider = dataProvider
            self.history = history // NEW
            
            switch mode {
            case .liked:
                self.listKey = "liked"
                self.likedService = LikedSongsService(
                    dataProvider: dataProvider,
                    sessionSeed: sessionSeed,
                    warmStartTarget: 100
                )
            case .playlist(let pl):
                self.listKey = "playlist:\(pl.id)"
                self.playlistService = PlaylistService(
                    dataProvider: dataProvider,
                    playlistID: pl.id
                )
            }
        }
    
    // MARK: - Public API
    
    /// Load initial deck of cards
    func load() async {
        // Load user/playlists if needed
        if service.user == nil { try? await service.loadMe() }
        if service.playlists.isEmpty { try? await service.loadPlaylists() }
        
        // Load reviewed tracks
        // NOTE: ReviewStore is still a pure actor, loaded directly.
        reviewedSet = await ReviewStore.shared.loadReviewed(for: listKey)
        
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
        // reset drag + glows
        dragX = 0
        leftIntensity = 0
        rightIntensity = 0
        
        // Mark as reviewed
        if let id = item.track?.id {
            await ReviewStore.shared.addReviewed(id, for: listKey)
            reviewedSet.insert(id)
        } else if let uri = item.track?.uri {
            await ReviewStore.shared.addReviewed(uri, for: listKey)
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
        Haptics.impactMedium()
        
        // Top up if needed
        await topUpIfNeeded()
    }
    
    /// Check if track is duplicate
    func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
    }
    
    /// Update drag offset and edge glow intensities
    func updateDragX(_ value: CGFloat) {
        dragX = value
        let (l, r) = SwipeDynamics.edgeIntensities(forDragX: value)
        if leftIntensity != l || rightIntensity != r {
            leftIntensity = l
            rightIntensity = r
        }
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
            
            // Continue fetching in background (now owned by the service)
            service.prefetchRemainingInBackground(reviewedIDs: reviewedSet) { [weak self] in
                guard let self else { return }
                Task { await self.topUpIfNeeded() }
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
            guard let service = likedService else { result = false; hasMore = false; return }
            result = await service.hasMore(cursor: nextCursor)
        case .playlist:
            guard let service = playlistService else { result = false; hasMore = false; return }
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
            try await service.batchUnsaveTracks(trackIDs: [id])
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
            history.add([entry]) // UPDATED to use coordinator
        } catch {
            print("Unsave failed:", error)
        }
    }
    
    private func removeFromPlaylist(plID: String, uri: String, track: Track) async {
        do {
            try await service.batchRemoveTracks(playlistID: plID, uris: [uri])
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
            history.add([entry]) // UPDATED to use coordinator
        } catch {
            print("Remove from playlist failed:", error)
        }
    }
    
    // MARK: - Helpers
    
    private var modePlaylistName: String? {
        if case .playlist(let pl) = mode { return pl.name }
        return nil
    }
}
