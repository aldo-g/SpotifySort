import SwiftUI

struct SortLikedView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router

    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showHistory = false

    @State private var nextURL: String? = nil
    @State private var isFetching = false
    @State private var allDone = false

    private let sessionSeed = UUID().uuidString
    private let pageSize = 20
    private let warmStartTarget = 100

    private let listKey = "liked"
    @State private var reviewedSet: Set<String> = []

    private var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return api.playlists }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }

    var body: some View {
        SelectrBackground {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView("Preparing deck…").task { await initialFastStart() }
                } else if topIndex >= deck.count {
                    if !allDone || nextCursor < orderedAll.count {
                        ProgressView("Loading more…").task { await topUpIfNeeded(force: true) }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "heart.slash.fill")
                                .font(.system(size: 40)).foregroundStyle(.white)
                            Text("All liked tracks reviewed")
                                .font(.title3).bold().foregroundStyle(.white)
                        }
                    }
                } else {
                    ZStack {
                        ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                            if idx >= topIndex, let tr = item.track {
                                SwipeCard(
                                    track: tr,
                                    addedAt: item.added_at,
                                    addedBy: item.added_by?.id,
                                    isDuplicate: false
                                ) { dir in
                                    onSwipe(direction: dir, item: item)
                                }
                                .padding(.horizontal, 16)
                                .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 8)
        }
        .selectrToolbar()
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .toolbar {
            // Title dropdown
            ToolbarItem(placement: .principal) {
                Menu {
                    Button { router.selectLiked() } label: {
                        Label("Liked Songs", systemImage: "heart.fill")
                    }
                    ForEach(ownedPlaylists, id: \.id) { pl in
                        Button { router.selectPlaylist(pl.id) } label: {
                            Text(pl.name).lineLimit(1)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Liked Songs").font(.headline).foregroundStyle(.white)
                        Image(systemName: "chevron.down").font(.subheadline).foregroundStyle(.white)
                    }
                }
            }
            // History button
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }
    }

    // MARK: Fast-start pipeline

    private func initialFastStart() async {
        if api.user == nil { try? await api.loadMe(auth: auth) }
        if api.playlists.isEmpty { try? await api.loadPlaylists(auth: auth) }

        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)
        while orderedAll.count < warmStartTarget, !allDone {
            await fetchNextPageAndMerge()
        }
        nextCursor = 0
        deck.removeAll()
        try? await loadNextPage()
        isLoading = false
        Task.detached { await backgroundFetchRemaining() }
    }

    private func backgroundFetchRemaining() async {
        while !allDone {
            await fetchNextPageAndMerge()
            await topUpIfNeeded()
        }
    }

    private func fetchNextPageAndMerge() async {
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

    // MARK: Deterministic shuffle with reviewed-last bias

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

    // MARK: Deck paging

    private func loadNextPage() async throws {
        let end = min(nextCursor + pageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck = Array(orderedAll.prefix(end))
        nextCursor = end
    }

    private func topUpIfNeeded(force: Bool = false) async {
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }
        try? await loadNextPage()
    }

    // MARK: Actions (auto-commit)

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        // mark reviewed immediately
        if let id = item.track?.id {
            ReviewStore.shared.addReviewed(id, for: listKey)
            reviewedSet.insert(id)
        } else if let uri = item.track?.uri {
            ReviewStore.shared.addReviewed(uri, for: listKey)
        }

        // auto-commit if swiped left
        if direction == .left, let tr = item.track, let id = tr.id {
            Task {
                await removeFromLiked(id: id, track: tr)
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
}

// Tiny hash (FNV-1a 64-bit)
private func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in s.utf8 { hash ^= UInt64(byte); hash &*= prime }
    return hash
}
