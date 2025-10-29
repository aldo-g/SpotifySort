import SwiftUI

// Unified sort screen that handles both Liked Songs and a specific Playlist.
// Add thin shims:
//   struct SortLikedView: View { var body: some View { SortScreen(mode: .liked) } }
//   struct SortView: View { let playlist: Playlist; var body: some View { SortScreen(mode: .playlist(playlist)) } }
enum SortMode { case liked, playlist(Playlist) }

struct SortScreen: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router

    let mode: SortMode

    // Shared deck state
    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0
    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showHistory = false

    // Dropdown state (screen-owned)
    @State private var isDropdownOpen = false

    // Global menu overlay
    @State private var showMenu = false

    // Liked-only paging/warm-start
    @State private var nextURL: String? = nil
    @State private var isFetching = false
    @State private var allDone = false
    private let warmStartTarget = 100
    private let likedPageSize = 20
    private let playlistPageSize = 20
    private let sessionSeed = UUID().uuidString

    // Dedupe/Reviewed
    @State private var reviewedSet: Set<String> = []
    @State private var duplicateIDs: Set<String> = []

    // NEW: live drag x from the foremost card (for edge glows)
    @State private var dragX: CGFloat = 0

    private var listKey: String {
        switch mode {
        case .liked: return "liked"
        case .playlist(let pl): return "playlist:\(pl.id)"
        }
    }

    private var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return api.playlists }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }

    private var chipTitle: String {
        switch mode {
        case .liked: return "Liked Songs"
        case .playlist(let pl): return pl.name
        }
    }

    private var currentPlaylistID: String? {
        if case .playlist(let pl) = mode { return pl.id }
        return nil
    }

    var body: some View {
        ZStack {
            // Background + content
            SelectrBackground {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView(mode.isLiked ? "Preparing deck…" : "Loading…")
                            .task { await initialLoad() }
                    } else if topIndex >= deck.count {
                        if moreToLoad {
                            ProgressView("Loading more…").task { await topUpIfNeeded(force: true) }
                        } else {
                            completionView
                        }
                    } else {
                        deckStack
                            .allowsHitTesting(!isDropdownOpen)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.top, 8)
            }

            // NEW: edge decision glows (green on left when dragging left; red on right when dragging right)
            EdgeGlows(intensityLeft: leftIntensity, intensityRight: rightIntensity)
                .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .tint(.white)

        // Custom top bar with centered selector + history on right
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                // Centered dropdown chip
                PlaylistSelector(
                    title: chipTitle,
                    playlists: ownedPlaylists,
                    currentID: currentPlaylistID,
                    includeLikedRow: true,
                    onSelectLiked: { router.selectLiked() },
                    onSelectPlaylist: { id in router.selectPlaylist(id) },
                    isOpen: $isDropdownOpen
                )

                // Right-aligned history button
                HStack {
                    Spacer()
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("History")
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.clear)
            .zIndex(2001)
        }

        // Render dropdown overlay anchored to the chip
        .overlayPreferenceValue(ChipBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if isDropdownOpen, let a = anchor {
                    let rect = proxy[a]
                    let width = max(rect.width, 260)
                    DropdownPanel(
                        width: width,
                        origin: CGPoint(x: rect.midX - width/2, y: rect.maxY + 8), // centered under chip
                        playlists: ownedPlaylists,
                        currentID: currentPlaylistID,
                        includeLikedRow: true,
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                isDropdownOpen = false
                            }
                        },
                        onSelectLiked: { router.selectLiked() },
                        onSelectPlaylist: { id in router.selectPlaylist(id) }
                    )
                }
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }

        // Hamburger + full overlay menu
        .overlay(MenuIconOverlay(isOpen: $showMenu), alignment: .topLeading)
        .overlay(
            AppMenu(isOpen: $showMenu) { action in
                switch action {
                case .liked:
                    router.selectLiked()
                case .history:
                    showHistory = true
                case .settings, .about:
                    break // hook up when you add routes
                }
            }
            .environmentObject(auth),
            alignment: .topLeading
        )
    }

    // MARK: - Computed intensities for glows (0...1), scaled to your 120pt swipe threshold
    private var leftIntensity: CGFloat {
        let v = max(0, min(1, (-dragX) / 120))
        return v
    }
    private var rightIntensity: CGFloat {
        let v = max(0, min(1, (dragX) / 120))
        return v
    }

    // MARK: - Subviews

    private var deckStack: some View {
        ZStack {
            ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                if idx >= topIndex, let tr = item.track {
                    let isTop = (item.id == deck[topIndex].id)
                    SwipeCard(
                        track: tr,
                        addedAt: item.added_at,
                        addedBy: item.added_by?.id,
                        isDuplicate: isDuplicate(trackID: tr.id),
                        onSwipe: { dir in onSwipe(direction: dir, item: item) },
                        // Only the foremost card reports live drag for glows
                        onDragX: isTop ? { dragX = $0 } : { _ in }
                    )
                    .padding(.horizontal, 16)
                    .zIndex(isTop ? 1 : 0)
                }
            }
        }
    }

    private var completionView: some View {
        Group {
            switch mode {
            case .liked:
                VStack(spacing: 10) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 40)).foregroundStyle(.white)
                    Text("All liked tracks reviewed")
                        .font(.title3).bold().foregroundStyle(.white)
                }
            case .playlist:
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40)).foregroundStyle(.white)
                    Text("All done!")
                        .font(.title2).bold().foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Loading / Paging

    private func initialLoad() async {
        if api.user == nil { try? await api.loadMe(auth: auth) }
        if api.playlists.isEmpty { try? await api.loadPlaylists(auth: auth) }

        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)

        switch mode {
        case .liked:
            // warm-start + first page for smoother start
            while orderedAll.count < warmStartTarget, !allDone {
                await fetchNextPageAndMergeLiked()
            }
            nextCursor = 0
            deck.removeAll()
            try? await loadNextPageLiked()
            isLoading = false
            Task.detached { await backgroundFetchRemainingLiked() }

        case .playlist(let pl):
            do {
                orderedAll = try await api.loadAllPlaylistTracksOrdered(
                    playlistID: pl.id, auth: auth, reviewedURIs: reviewedSet
                )
                recomputeDuplicates()
                deck.removeAll()
                nextCursor = 0
                try? await loadNextPagePlaylist()
                isLoading = false
            } catch {
                print(error)
                isLoading = false
            }
        }
    }

    private var moreToLoad: Bool {
        switch mode {
        case .liked:
            return !allDone || nextCursor < orderedAll.count
        case .playlist:
            return nextCursor < orderedAll.count
        }
    }

    // Liked: background prefetch
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
                allDone = (nextURL == nil); return
            }
            orderedAll.append(contentsOf: result.items)
            orderedAll.sort { a, b in rankKey(a) < rankKey(b) }
            if nextURL == nil { allDone = true }
        } catch {
            allDone = true
            print("SavedTracks paging error: \(error)")
        }
    }

    private func loadNextPageLiked() async throws {
        let end = min(nextCursor + likedPageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck = Array(orderedAll.prefix(end))
        nextCursor = end
    }

    private func loadNextPagePlaylist() async throws {
        let end = min(nextCursor + playlistPageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck.append(contentsOf: orderedAll[nextCursor..<end])
        nextCursor = end
    }

    private func topUpIfNeeded(force: Bool = false) async {
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }
        switch mode {
        case .liked: try? await loadNextPageLiked()
        case .playlist: try? await loadNextPagePlaylist()
        }
    }

    // MARK: - Dedupe / Ranking

    private func recomputeDuplicates() {
        var counts: [String: Int] = [:]
        for it in orderedAll {
            if let id = it.track?.id { counts[id, default: 0] += 1 }
        }
        duplicateIDs = Set(counts.filter { $0.value > 1 }.map { $0.key })
    }

    private func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
    }

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

    // MARK: - Actions (auto-commit)

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        // Reset glow immediately so it doesn't linger during the exit animation
        dragX = 0

        switch mode {
        case .liked:
            if let id = item.track?.id {
                ReviewStore.shared.addReviewed(id, for: listKey)
                reviewedSet.insert(id)
            } else if let uri = item.track?.uri {
                ReviewStore.shared.addReviewed(uri, for: listKey)
            }
            if direction == .left, let tr = item.track, let id = tr.id {
                Task { await removeFromLiked(id: id, track: tr) }
            }

        case .playlist(let pl):
            if let uri = item.track?.uri { ReviewStore.shared.addReviewed(uri, for: listKey) }
            if direction == .left, let tr = item.track, let uri = tr.uri {
                Task { await removeFromPlaylist(plID: pl.id, uri: uri, track: tr) }
            }
        }

        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

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
            await MainActor.run { HistoryStore.shared.add([entry]) }
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
                playlistName: (currentPlaylistID == plID ? chipTitle : nil),
                trackID: track.id,
                trackURI: track.uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            await MainActor.run { HistoryStore.shared.add([entry]) }
        } catch {
            print("Remove from playlist failed:", error)
        }
    }
}

// Tiny hash (FNV-1a 64-bit)
private func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in s.utf8 { hash ^= UInt64(byte); hash &*= prime }
    return hash
}

// Convenience
private extension SortMode {
    var isLiked: Bool { if case .liked = self { return true } else { return false } }
}

// MARK: - Edge glow view
private struct EdgeGlows: View {
    var intensityLeft: CGFloat   // 0...1
    var intensityRight: CGFloat  // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // LEFT (green → transparent)
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.55 * intensityLeft),
                        Color.red.opacity(0.28 * intensityLeft),
                        .clear
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.42) // under half width feels subtle
                .blur(radius: 22)
                .blendMode(.screen)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, alignment: .leading)

                // RIGHT (red → transparent)
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.55 * intensityRight),
                        Color.green.opacity(0.28 * intensityRight),
                        .clear
                    ],
                    startPoint: .trailing, endPoint: .leading
                )
                .frame(width: geo.size.width * 0.42)
                .blur(radius: 22)
                .blendMode(.screen)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
