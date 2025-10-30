import SwiftUI

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

    // Edge glow
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
                        // NUDGE: lift the card stack slightly
                        deckStack
                            .padding(.top, -50)
                            .allowsHitTesting(!isDropdownOpen)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.top, 8)
            }

            EdgeGlows(intensityLeft: leftIntensity, intensityRight: rightIntensity)
                .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .tint(.white)

        // === TOP BAR ===
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

                // Left menu & right history — glass buttons re-styled to blend with chip
                HStack {
                    GlassIconButton(system: "line.3.horizontal") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showMenu.toggle()
                        }
                    }

                    Spacer()

                    GlassIconButton(system: "clock.arrow.circlepath") {
                        showHistory = true
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

        // Dropdown overlay
        .overlayPreferenceValue(ChipBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if isDropdownOpen, let a = anchor {
                    let rect = proxy[a]
                    let width = max(rect.width, 260)
                    DropdownPanel(
                        width: width,
                        origin: CGPoint(x: rect.midX - width/2, y: rect.maxY + 8),
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

        // Full-screen menu sheet
        .overlay(
            AppMenu(isOpen: $showMenu) { action in
                switch action {
                case .liked: router.selectLiked()
                case .history: showHistory = true
                case .settings, .about: break
                }
            }
            .environmentObject(auth),
            alignment: .topLeading
        )
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }
    }

    // MARK: Glow intensity
    private var leftIntensity: CGFloat { max(0, min(1, (-dragX) / 120)) }
    private var rightIntensity: CGFloat { max(0, min(1, (dragX) / 120)) }

    // MARK: Deck
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
                        onDragX: isTop ? { dragX = $0 } : { _ in }
                    )
                    .padding(.horizontal, 16)
                    .zIndex(isTop ? 1 : 0)
                }
            }
        }
    }

    // MARK: Completion
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
                    Text("All done!").font(.title2).bold().foregroundStyle(.white)
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
            // ✅ STEP 1b: Use PagingHelper for warm start check
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
                // ✅ STEP 1a: Use DuplicateDetector (async, off main thread)
                duplicateIDs = await DuplicateDetector.detect(orderedAll)
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

    // ✅ STEP 1b: Use PagingHelper for "has more" logic
    private var moreToLoad: Bool {
        switch mode {
        case .liked:
            return PagingHelper.hasMore(
                currentCursor: nextCursor,
                totalCount: orderedAll.count,
                isRemoteComplete: allDone
            )
        case .playlist:
            return PagingHelper.hasMore(
                currentCursor: nextCursor,
                totalCount: orderedAll.count
            )
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
                allDone = (nextURL == nil); return
            }
            orderedAll.append(contentsOf: result.items)
            // ✅ STEP 1c: Use DeckRanker for sorting
            orderedAll = DeckRanker.sort(orderedAll, reviewedIDs: reviewedSet, sessionSeed: sessionSeed)
            if nextURL == nil { allDone = true }
        } catch {
            allDone = true
            print("SavedTracks paging error: \(error)")
        }
    }

    private func loadNextPageLiked() async throws {
        // ✅ STEP 1b: Use PagingHelper for page extraction
        guard let range = PagingHelper.nextPageRange(
            currentCursor: nextCursor,
            pageSize: likedPageSize,
            totalCount: orderedAll.count
        ) else { return }
        
        deck = Array(orderedAll.prefix(range.upperBound))
        nextCursor = range.upperBound
    }

    private func loadNextPagePlaylist() async throws {
        // ✅ STEP 1b: Use PagingHelper for page extraction
        let page = PagingHelper.extractPage(
            from: orderedAll,
            currentCursor: nextCursor,
            pageSize: playlistPageSize
        )
        guard !page.isEmpty else { return }
        
        deck.append(contentsOf: page)
        nextCursor += page.count
    }

    private func topUpIfNeeded(force: Bool = false) async {
        // ✅ STEP 1b: Use PagingHelper for threshold check
        let shouldLoad = force || PagingHelper.shouldTopUp(
            currentPosition: topIndex,
            deckSize: deck.count,
            threshold: 5
        )
        guard shouldLoad else { return }
        
        switch mode {
        case .liked: try? await loadNextPageLiked()
        case .playlist: try? await loadNextPagePlaylist()
        }
    }

    // MARK: - Dedupe

    private func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
    }

    // MARK: - Actions (auto-commit)
    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
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

// === Glass icon button (unchanged) ===
private struct GlassIconButton: View {
    let system: String
    let action: () -> Void
    private let size: CGFloat = 34
    private let radius: CGFloat = 10

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                            .blendMode(.multiply)
                    )
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .overlay(
                        BrickOverlay(opacity: 0.12)
                            .blendMode(.overlay)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .inset(by: 0.5)
                            .stroke(.black.opacity(0.22), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)

                Image(systemName: system)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edge glow (unchanged)
private struct EdgeGlows: View {
    var intensityLeft: CGFloat
    var intensityRight: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color.red.opacity(0.55 * intensityLeft),
                             Color.red.opacity(0.28 * intensityLeft),
                             .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.42)
                .blur(radius: 22)
                .blendMode(.screen)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, alignment: .leading)

                LinearGradient(
                    colors: [Color.green.opacity(0.55 * intensityRight),
                             Color.green.opacity(0.28 * intensityRight),
                             .clear],
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

private extension SortMode {
    var isLiked: Bool { if case .liked = self { return true } else { return false } }
}
